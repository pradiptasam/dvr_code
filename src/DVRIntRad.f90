module DVRIntRad

  use constants
  use DVRData
  use radial_mod 
  use dvr_diag_mod

  implicit none

  contains

  subroutine GetRadialElements()

    integer                    :: i, j, a, b, l, l_val, error
    integer                    :: nr_limit !Only use up to this amount of
                                           !DVR primitives 
    logical                    :: inversion_check, alternative_formula
    integer, allocatable       :: ipiv(:)
    real(idp), allocatable     :: work(:)

    real(idp), allocatable     :: matrix(:,:)
    real(idp), allocatable     :: matrix_full(:,:), matrix_diag(:,:)
    real(idp), allocatable     :: matrix_single(:,:), matrix_single_full(:,:)
    real(idp), allocatable     :: matrix_single_all(:,:,:)
    real(idp), allocatable     :: matrix_all(:,:,:), matrix_inv_all(:,:,:), unity(:,:)
    real(dp), pointer          :: pot_1(:), pot_2(:)

    nr_limit           = 201
    inversion_check    = .true.
    ! 'alternative_formula' avoids some numerical issues with small denominators
    alternative_formula= .true.
 
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!! Get Eigenvalues !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    
    !! Get banded storage format of Hamiltonian matrix in the FEM-DVR basis
!   call get_real_surf_matrix_cardinal(matrix_diag, grid, pot, Tkin_cardinal)
!
!   !! Diagonalize Hamiltonian matrix which is stored in banded format.
!   !! nev specifies the first nev eigenvalues and eigenvectors to be extracted.
!   !! If needed, just add more
!   call diag_arpack_real_sym_matrix(matrix_diag, formt='banded',                &
!   &    n=size(matrix_diag(1,:)), nev=nint(0.5*para%nr), which='SA',            &
!   &    eigenvals=eigen_vals, rvec=.true.)
  
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!! Single-Particle Matrix Element !!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 
    ! First we treat the single-particle matrix element T + V_ne, the radial
    ! potential is then given by Z / r plus the rotational barrier
    ! We overwrite here the previous pot file which was obtained from a fixed 
    ! potential file

    
    allocate(matrix_single_all(size(grid%r), size(grid%r), para%l+1), stat=error)
    call allocerror(error)

    do l = 1, para%l + 1
      l_val = l-1
      do i = 1, size(pot(:,1))
        pot(i, l) = real(para%Z, idp) / grid%r(i)   +                                   &
        &        real(l_val * (l_val + 1), idp) / (two * para%mass * grid%r(i)**2)
      end do

        
      pot_1 => pot(:,l)

      ! Get banded storage format of Hamiltonian matrix in the FEM-DVR basis
      call get_real_surf_matrix_cardinal(matrix_single, grid, pot_1, Tkin_cardinal)
      
      !! Convert banded matrix to full matrix
      !! Watch for the para%nr-2, because the end points are not included anymore
      call mat_banded_to_full(matrix_single_full, matrix_single, para%nr-2, 0,     &
      &                       para%nl)
      
      do i = 1, size(matrix_single_all(:,1,l))
        do j = 1, size(matrix_single_all(:,1,l))
          if (i .le. j) then
            matrix_single_all(i,j,l) = matrix_single_full(i,j)
          else
            matrix_single_all(i,j,l) = matrix_single_full(j,i)
          end if
        end do
      end do
      
      open(11, file="singleparticle_rad_elements_l"//trim(int2str(l_val))//".dat",&
      &    form="formatted", action="write")
      write(11,*) '# Primitive Radial Matrix Elements for the Two-index '//        &
      &           'Integrals for l = '//trim(int2str(l_val))
      do a = 1, size(matrix_single_all(1,:,l))
        if (a > nr_limit) cycle
        !if (only_bound) then
        !  if (a > 0.5*para%nr - 1) cycle
        !  if (eigen_vals(a) < zero) cycle
        !end if
        do b = 1, size(matrix_single_all(1,:,l))
          if (b > nr_limit) cycle
          !if (only_bound) then
          !  if (b > 0.5*para%nr - 1) cycle
          !  if (eigen_vals(b) < zero) cycle
          !end if
          if (abs(matrix_single_all(a,b,l)).gt.1e-12) &
          & write(11, '(2I8,ES25.17)') a, b, matrix_single_all(a,b,l)
          !write(11, '(3ES25.17)') real(a), real(b), matrix_single_all(a,b)
        end do
      end do
      close(11)

    end do


    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!! Two-Particle Matrix Element !!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    
    allocate(matrix_all(size(grid%r),size(grid%r), para%l+1),  stat=error)
    call allocerror(error)
  
    allocate(matrix_inv_all(size(grid%r),size(grid%r), para%l+1),  stat=error)
    call allocerror(error)
  
    allocate(unity(size(grid%r),size(grid%r)), stat=error)
    call allocerror(error)

    ! Set the potential to only include the rotational barrier to only treat the
    ! kinetic part in the following
    do l = 1, para%l + 1
      l_val = l-1
      do i = 1, size(pot(:,1))
        pot(i, l) = pot(i, l) +                                                          &
         &        real(l_val * (l_val + 1), idp) / (two * para%mass * grid%r(i)**2)
      end do

      pot_2 => pot(:,l)

      ! Get banded storage format of Hamiltonian matrix in the FEM-DVR basis
      call get_real_surf_matrix_cardinal(matrix, grid, pot_2, Tkin_cardinal)
  
      ! Remove 1/(2m) factor from kinetic operator to obtain properly
      ! scaled radial matrix elements
      matrix = (two * para%mass) * matrix
  
      matrix_full = zero
      !! Convert banded matrix to full matrix
      !! Watch for the para%nr-2, because the end points are not included anymore
      call mat_banded_to_full(matrix_full, matrix, para%nr-2, 0, para%nl)
 
      if (inversion_check) then
 
        do i = 1, size(matrix_all(:,1, l))
          do j = 1, size(matrix_all(:,1, l))
            if (i .le. j) then
              matrix_all(i,j,l) = matrix_full(i,j)
            else
              matrix_all(i,j,l) = matrix_full(j,i)
            end if
          end do
        end do
      end if

      ! Invert radial kinetic matrix
      if (allocated(ipiv)) deallocate(ipiv)
      allocate(ipiv(size(matrix_full(1,:))), stat=error)
      call allocerror(error)
      if (allocated(work)) deallocate(work)
      allocate(work(size(matrix_full(1,:))), stat=error)
      call allocerror(error)
 
      call wrap_dsytrf(matrix_full, size(matrix_full(1,:)), ipiv, work)
      call wrap_dsytri(matrix_full, size(matrix_full(1,:)), ipiv, work)
 
      do i = 1, size(matrix_inv_all(:,1,l))
        do j = 1, size(matrix_inv_all(:,1,l))
          if (i .le. j) then
            matrix_inv_all(i,j,l) = matrix_full(i,j)
          else
            matrix_inv_all(i,j,l) = matrix_full(j,i)
          end if
        end do
      end do

      if (inversion_check) then
 
        unity = matmul(matrix_inv_all(:,:,l), matrix_all(:,:,l))
        do i = 1, size(unity(:,1))
          do j = 1, size(unity(:,1))
            if (i == j) cycle
            if (abs(unity(i,j)) > 1d-10) then
              write(*,*) "WARNING: Inversion not successful with desired precision."
            end if
            if (abs(unity(i,j)) > 1d-4) then
              write(*,*) "ERROR: Inversion not successful."
            end if
          end do
        end do
 
      end if

      open(11, file="twoparticle_rad_elements_l"//trim(int2str(l_val))//".dat",   &
      &    form="formatted", action="write")
      write(11,*) '# Primitive Radial Matrix Elements for the Four-index '//       &
      &           'Integrals for l = '//trim(int2str(l_val))
      do a = 1, size(matrix_full(1,:))
        if (a > nr_limit) cycle
        !if (only_bound) then
        !  if (a > 0.5*para%nr - 1) cycle
        !  if (eigen_vals(a) < zero) cycle
        !end if
        do b = 1, size(matrix_full(1,:))
          if (b > nr_limit) cycle
          !if (only_bound) then
          !  if (b > 0.5*para%nr - 1) cycle
          !  if (eigen_vals(b) < zero) cycle
          !end if
          if (alternative_formula) then
            write(11, '(2I8,ES25.17)') a, b,                                       &
            & ((real(2*l_val+1, idp) / (grid%r(a) * sqrt(grid%weights(a)) *            &
            &     grid%r(b) * sqrt(grid%weights(b)))) * matrix_inv_all(a,b,l))       &
            & + ((grid%r(a) * grid%r(b)) / full_r_max)**l_val *                        &
            &   (one / (full_r_max**(l_val+1)))
            !write(11, '(3ES25.17)') real(a), real(b),                              &
            !& ((real(2*l_val+1, idp) / (grid%r(a) * sqrt(grid%weights(a)) *            &
            !&     grid%r(b) * sqrt(grid%weights(b)))) * matrix_inv_all(a,b,l))       &
            !& + ((grid%r(a) * grid%r(b)) / full_r_max)**l_val *                        &
            !&   (one / (full_r_max**(l_val+1)))
          else
            write(11, '(2I8,ES25.17)') a, b,                                       &
            & ((real(2*l_val+1, idp) / (grid%r(a) * sqrt(grid%weights(a)) *            &
            &     grid%r(b) * sqrt(grid%weights(b)))) * matrix_inv_all(a,b,l))       &
            & + ((grid%r(a)**l_val * grid%r(b)**l_val) / full_r_max**(2*l_val+1))
            !write(11, '(3ES25.17)') real(a), real(b),                              &
            !& ((real(2*l_val+1, idp) / (grid%r(a) * sqrt(grid%weights(a)) *            &
            !&     grid%r(b) * sqrt(grid%weights(b)))) * matrix_inv_all(a,b,l))       &
            !& + ((grid%r(a)**l_val * grid%r(b)**l_val) / full_r_max**(2*l_val+1))
          end if
        end do
      end do
      close(11)

    end do
    stop

    deallocate(ipiv, work)
  end subroutine GetRadialElements

end module DVRIntRad
