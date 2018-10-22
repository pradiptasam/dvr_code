module DVRDiag

  use DVRData
  use InputData
  use dvr_diag_mod
  use dvr_init_mod

  implicit none

  contains

  subroutine SetDVR()

    integer  :: i, l, l_val
    real(dp),  allocatable    :: file_r(:)     ! Temporary arrays to store the distances
    real(dp), target, allocatable    :: file_pot(:,:) ! Temporary arrays to store the potential
    real(dp),  pointer :: pot_new(:), pot_old(:)

    para%pottype       = 'file' ! 'density_file', 'file', 'analytical'
    para%pot_filename  = 'input_pot.in'
    para%r_min         = r_min
    para%r_max         = r_max
    para%m             = m
    para%nl            = nl
    para%nr            = m*nl + 1
    para%ng            = m*nl - 1
    para%l             = l_max !Rotational quantum number
    para%Z             = z
    para%mass          = mass
    if (nev_fac.eq.1.0d0) then
      para%nev = para%nr - 2
    else
      para%nev           = nint(nev_fac*para%nr)
    end if
 
    para%mapped_grid   = mapped_grid
    para%maptype       = 'diff'
    para%read_envelope = ''
    para%beta          = beta
    para%E_max         = 1d-5

    write(iout, *) '**********'
    write(iout, *) 'Setting up these parameters:'
    write(iout, '(X,A,3X, F6.2)') 'para%r_min     =', r_min
    write(iout, '(X,A,3X, F6.2)') 'para%r_max     =', r_max
    write(iout, '(X,A,3X, I6)') 'para%m         =', m
    write(iout, '(X,A,3X, I6)') 'para%nl        =', nl
    write(iout, '(X,A,3X, I6)') 'para%nr        =', para%nr
    write(iout, '(X,A,3X, I6)') 'para%l_max     =', l_max
    write(iout, '(X,A,3X, I6)') 'para%nev     =', para%nev
    write(iout, '(X,A,3X, I6)') 'para%Z         =', z
    write(iout, '(X,A,3X, F6.2)') 'para%mass      =', mass
    write(iout, *) '***********' 

    call init_grid_dim_GLL(grid, para) 
 
    ! Note that later on the first and final grid point are removed from the grid
    ! Since we need for the matrix elements the value of r_max of the original,
    ! full grid, it will be stored here
    full_r_max = maxval(grid%r)

    allocate(pot(size(grid%r), 2*para%l+1))

    if (para%pottype == 'analytical') then
      write(*,*) 'Using analytical potential'
      do i = 1,size(pot(:,1))
         pot(i,:) = analytical_potential(grid%r(i), para%mass)
      end do
    elseif ((para%pottype == 'file') .or. (para%pottype == 'density_file')) then
      write(iout,*) 'Using potential from file '//trim(para%pot_filename)
      write(iout,*) '  '
      call init_grid_op_file_1d_all(file_pot, file_r, para)

      do l = 1, 2*para%l + 1
        l_val = l + 1
        pot_old => file_pot(:,l)
        pot_new => pot(:,l)
        call map_op(grid%r, pot_new, file_r, pot_old) !Perform splining
      end do
    else
      write(*,*) "ERROR: Invalid pottype"
    end if
    call init_work_cardinalbase(Tkin_cardinal, grid, para%mass)
    call redefine_ops_cardinal(para, pot)
    call redefine_GLL_grid_1d(grid)
 
    write(iout, *) 'Grid initialization is done.'

    deallocate(file_r, file_pot)

  end subroutine SetDVR

  subroutine DVRDiagonalization()

    integer                    :: i, j, l, l_val, error
    real(dp), allocatable      :: matrix(:,:)
    logical                    :: only_bound ! Only writes out bound states
    real(dp), pointer          :: pot_1(:)
    real(dp), pointer          :: eigenval_p(:)

    real                       :: start, finish

!   only_bound         = .true.
    only_bound         = .false.
        
    ! Write potential 
    open(11, file="input_pot.out", form="formatted", &
    &    action="write")
    write(11,*) '# input potential after splining and adjusting to GLL grid'
    do i = 1, size(pot(:,1))
      write(11,*) grid%r(i), pot(i,1)
    end do
    close(11)
 
    !! Allocate the arrays for eigenvalues and eigenvectors

    allocate(eigen_vals(para%nev, 2*para%l+1),stat=error)
    call allocerror(error)

    allocate(eigen_vecs(size(grid%r), para%nev, 2*para%l+1),stat=error)
    call allocerror(error)

    !! Here start the loop over different values of the angular quantum number
!   do l = 1, 2*para%l+1
    do l = 1, para%l+1

      l_val = l-1
      write(iout, *) 'Solving the radial Schroedinger equation for l = ', l_val

      pot_1 => pot(:,l)
      eigenval_p => eigen_vals(:,l)


      !! Get banded storage format of Hamiltonian matrix in the FEM-DVR basis
      call get_real_surf_matrix_cardinal(matrix, grid, pot_1, Tkin_cardinal)
  
      call cpu_time(start)

      !! Diagonalize Hamiltonian matrix which is stored in banded format.
      !! nev specifies the first nev eigenvalues and eigenvectors to be extracted.
      !! If needed, just add more
      call diag_arpack_real_sym_matrix(matrix, formt='banded', n=size(matrix(1,:)), &
      &                   nev=para%nev, which='SA', eigenvals=eigenval_p, &
      &                   rvec=.true.)
  
      call cpu_time(finish)

      write(iout,'(X,a,X,f10.5,X,a)') 'Time taken for diagonalization = ', finish-start, 'seconds.'

      do i = 1, size(matrix(:,1))
        do j = 1, size(matrix(1,:))
!         eigen_vecs(i,j,l)  = matrix(i,j) / (sqrt(grid%weights(i)) * grid%r(i))
!         eigen_vecs(i,j,l)  = matrix(i,j) * (sqrt(grid%weights(i)) )
          eigen_vecs(i,j,l)  = matrix(i,j)
        end do
      end do
      

      if ( debug.gt.5) then
        write(iout,'(X,90a)') 'Writing down the eigenvalues, eigenvectors and combining coefficients as demanded ...'
        ! Write eigenvalues.
        open(11, file="eigenvalues_GLL"//trim(int2str(l_val))//".dat", form="formatted", &
        &    action="write")
        write(11,*) '#_______________________________________________________________'
        write(11,*) "#              eigenvalues for hydrogen with l = ", trim(int2str(l_val))
        write(11,*) '#_______________________________________________________________'
        write(11,*) "#     index    -    eigenvalue    -    eigenvector normalization"
        write(11,*) ""
        do i = 1, size(eigen_vals(:,l))
          write(11,'(I8,3ES25.17)') i-1, eigen_vals(i,l),                              &
!         &                         - one / (two * (real(i+l_val, idp))**2),        &
          &                         dot_product(matrix(:,i), matrix(:,i))
        end do
        close(11)
    
        ! Write eigenvectors. Here, if we want to represent the eigenvectors in the
        ! physical grid instead of numerical grid defined by the normalized FEM-BASIS,
        ! we should divide by the square root of the Gaussian interpolating weights,
        ! see eg. arXiv:1611.09034 (2016).
        ! We furthermore divide by r such that we obtain the proper radial
        ! wavefunction psi(r) instead of the rescaled object u(r) = psi(r) * r
    
        if (only_bound) then
          open(11, file="eigenvectors_GLL"//trim(int2str(l_val))//".dat", form="formatted",&
          &    action="write", recl=100000)
          do i = 1, size(matrix(:,1))
            write(11,'(ES25.17, 1x)', advance = 'No') grid%r(i)
            do j = 1, size(matrix(i,:))
              if (eigen_vals(j,l) > zero) cycle
              write(11,'(ES25.17, 1x)', advance = 'No')                              &
              & eigen_vecs(i,j,l)/ (sqrt(grid%weights(i)) * grid%r(i))
            end do
            write(11,*) ' '
            write(76,'(i5,f15.8)') i, grid%r(i)
          end do
          close(11)
        else
          open(11, file="eigenvectors_GLL"//trim(int2str(l_val))//".dat", form="formatted",&
          &    action="write", recl=100000)
          do i = 1, size(matrix(:,1))
            write(11,*) grid%r(i), (eigen_vecs(i,j,l)/(sqrt(grid%weights(i)) * grid%r(i)), &
            & j = 1, size(matrix(i,:)))
          end do
          close(11)
        end if
        
        ! Write transformation matrix. This is the same as the eigenvectors except
        ! without the grid as the first column 
        if (only_bound) then
          open(11, file="transformation_matrix_l"//trim(int2str(l_val))//".dat",    &
          &    form="formatted", action="write")
          do i = 1, size(matrix(:,1))
            do j = 1, size(matrix(i,:))
              if (eigen_vals(j,l) > zero) cycle
              write(11,'(ES25.17, 1x)', advance = 'No')                              &
              & eigen_vecs(i,j,l)
            end do
            write(11,*) ' '
          end do
          close(11)
        else
          open(11, file="transformation_matrix_l"//trim(int2str(l_val))//".dat",    &
          &    form="formatted", action="write")
          do i = 1, size(matrix(:,1))
            write(11,*)                               &
            & (eigen_vecs(i,j,l),                    &
            & j = 1, size(matrix(i,:)))
          end do
          close(11)
        end if

      end if  ! if files are written out

    end do

    deallocate(matrix)
  end subroutine DVRDiagonalization

end module DVRDiag
