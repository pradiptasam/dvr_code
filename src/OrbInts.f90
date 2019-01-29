module OrbInts

  use constants
  use util_mod, only : stop_all, allocerror
  use ReadInput, only : n_max, two_e_int, nfrz, shift_int
  use OrbData
  use CombineInts, only : CombineOrbInts, CombineOrbInts_old
  use CombineInts_alt, only : CombineOrbInts_alt, Calc2eRadOrbInts_alt

  implicit none

  contains

  subroutine SetOrbData()

    use DVRData, only : para
    use util_mod, only : allocerror

    integer :: i, j, k, l_val, i_o, indx, error

    if (para%split_grid) then
      if (n_max(2) == -1) n_max(2) = n_max(1)
      orb%n_inner = n_max(1)
      orb%n_outer = n_max(2)
      orb%n_max = sum(n_max)
      orb%shift_int = shift_int
    else 
      orb%n_max = n_max(1)
    end if

    allocate(SpatialOrbInd(orb%n_max,para%l+1,2*para%l+1),stat=error)
    call allocerror(error)

    SpatialOrbInd = 0

    indx = 0
    do i = 1, orb%n_max
      l_val = min(i,para%l+1)
!     write(*,*) 'limit for l_val:', l_val
      do j = 1, l_val
        do k = 1, 2*j-1
          indx = indx + 1
          SpatialOrbInd(i-j+1,j,k) = indx
!         write(iout, *) i-j+1, j, k, SpatialOrbInd(i-j+1, j, k)
        end do
      end do
    end do

    orb%nSpatialOrbs = indx

    nFrozen = nfrz

    write(iout, *) '**********'
    write(iout, *) 'Setting up these parameters for the orbitals:'
    write(iout, '(X,A,3X, I6)') 'orb%n_max     =', orb%n_max
    if (para%split_grid) then
      write(iout, '(X,A,3X, I6)') 'orb%n_inner     =', orb%n_inner
      write(iout, '(X,A,3X, I6)') 'orb%n_outer     =', orb%n_outer
    end if
    write(iout, '(X,A,3X, I6)') 'orb%nSpatialOrbs     =', indx
    write(iout, *) '***********' 

!   do i =  1, n_max
!     do j = 1, para%l+1
!       do k = 1, 2*para%l+1
!         write(76,'(4I5)') i, j, k, SpatialOrbInd(i,j,k)
!         if (SpatialOrbInd(i,j,k).ne.0) write(77,'(4I5)') i, j, k, SpatialOrbInd(i,j,k)
!       end do
!     end do
!   end do  
    
!   write(iout,*) 'Total number of spatial orbital', nSpatialOrbs

  end subroutine SetOrbData

! ***********************
  subroutine GetOrbInts()

    use DVRData, only : para, eigen_vecs

    real(dp) :: tol
    logical  :: all4

    real(dp), allocatable :: EigVecs(:,:,:)

    all4 = two_e_int.eq.1
!   all4 = .true.
!   all4 = .false.

    tol = 1e-12

    call SetOrbData()

    if (para%split_grid) call SetUpEigVec(eigen_vecs, EigVecs)

    if (para%split_grid) then
      call Calc1eOrbInts(EigVecs)
      !call Calc1eOrbInts(eigen_vecs)
    else
      call Calc1eOrbInts(eigen_vecs)
    end if

    if (all4) then

      if (para%split_grid) then
        !call Calc2eRadOrbInts(EigVecs)
        call Calc2eRadOrbInts(eigen_vecs)
      else
        call Calc2eRadOrbInts(eigen_vecs)
      end if
      call CombineOrbInts()

    else 

      if (para%split_grid) then
        !call Calc2eRadOrbInts_alt(EigVecs)
        call Calc2eRadOrbInts_alt(eigen_vecs)
      else
        call Calc2eRadOrbInts_alt(eigen_vecs)
      end if
      call CombineOrbInts_alt()
 
    end if
  
    file_int = 'FCIDUMP'

    call WriteInts(tol)

  end subroutine GetOrbInts
! ***********************

  subroutine SetUpEigVec(VecsOld, EigVecs)

    use DVRData, only : para, grid

    real(dp), allocatable, intent(in) :: VecsOld(:,:,:)
    real(dp), allocatable, intent(inout) :: EigVecs(:,:,:)

    integer :: len_1, len_2, len_mid, i, j

    len_1 = para%m1*para%nl
    len_2 = para%m2*para%nl - 1
    if (orb%shift_int) then
      len_mid = para%m1*para%nl + orb%n_inner
    else
      len_mid = para%m1*para%nl
    end if

    write(iout, *) 'The integrals are now calculated for orbitals taken from two separated regions.'
    write(iout, '(a, i3)') ' Orbitals from the inner region: 1 -', len_1
    write(iout, '(a,i3,a,i3)') ' Orbitals from the outer region: ', len_mid+1, ' -', len_mid+len_2
    if (.not.orb%shift_int) write(iout, *) '***Orbitals are not shifted in the outer region***'

!   do i = 1, size(grid%r)
!     write(78, '(11f10.6)') (VecsOld(i,j,1), j=1, size(VecsOld(1,:,3)))
!   end do

    allocate(EigVecs(size(grid%r),orb%n_max,para%l+1))
    EigVecs = 0.0d0
    do i = 1, len_1
      do j = 1, orb%n_inner
        EigVecs(i,j,:) = VecsOld(i,j,:)
      end do
    end do

    if (orb%n_outer == 0) return

    do i = 1, len_2
      do j = 1, orb%n_outer
        EigVecs(i+len_1,j+orb%n_inner,:) = VecsOld(i+len_1,j+len_mid,:)
      end do
    end do

!   do i = 1, size(grid%r)
!     write(79, '(11f10.6)') (EigVecs(i,j,1), j=1, size(EigVecs(1,:,3)))
!   end do

  end subroutine SetUpEigVec

  subroutine Calc1eOrbInts(EigVecs)

    use DVRData, only : one_e_rad_int, para, grid

    real(dp), allocatable, intent(in) :: EigVecs(:,:,:)
    integer  :: i, j, l, l_val, m, n, error, ml, ind_1, ind_2
    real(dp) :: int_value, start, finish

    real(dp), allocatable :: inter_int(:,:)

    call cpu_time(start)

    allocate(inter_int(para%ng,orb%n_max), stat=error)
    call allocerror(error)

    allocate(OneEInts(orb%nSpatialOrbs,orb%nSpatialOrbs), stat=error)
    call allocerror(error)

    OneEInts = zero

    ! The transformation of 1e integrals is done in two steps
    ! i and j are basis indices, while m and n are orbital indices
    ! h_{ij} -> h_{mn} using transformation matrix b_{in}
    ! First step: h_{in} = \sum_j h_{ij} b_{in} 
    ! Second step: h_{mn} = \sum_i b^*_{im} h_{in} 

    ! The calculation is done over a loop of l

    do l = 1, para%l + 1
!   do l = 1, 1
      l_val = l - 1

      ! The first step is done here
      do n = 1, orb%n_max - (l-1)
        do i = 1, para%ng

          int_value = 0.0d0
          do j = 1, para%ng
             int_value = int_value + one_e_rad_int(i,j,l)*EigVecs(j,n,l)
!            write(77,'(3i4,3f20.10)') i, n, l, one_e_rad_int(i,j,l),EigVecs(j,n,l),int_value
          end do 
          inter_int(i,n) = int_value
!         write(iout,*) i, n, l, int_value
        end do 
      end do ! end loop over n_max

!     write(iout,*) 'The second step'
      ! The second step is done here, still it is inside the loop of l
      do m = 1, orb%n_max - (l-1)
        do n = 1, orb%n_max - (l-1)

          int_value = 0.0d0
          do i = 1, para%ng
            int_value = int_value + EigVecs(i,m,l) * inter_int(i,n)
!            write(78,'(3i4,3f20.10)') m, n, l, inter_int(i,n), EigVecs(i,m,l), int_value
          end do

!         write(iout,*) m, n, l, int_value

          do ml = 1, 2*l_val+1
!           ind_1 = SpatialOrbInd(m+l-1, l, ml)
            ind_1 = SpatialOrbInd(m, l, ml)
            if (ind_1.eq.0) write(iout,*) 'ind_1', m, l, ml, ind_1
!           ind_2 = SpatialOrbInd(n+l-1, l, ml)
            ind_2 = SpatialOrbInd(n, l, ml)
            if (ind_2.eq.0) write(iout,*) 'ind_2', n, l, ml, ind_2
            OneEInts(ind_1, ind_2) = int_value
!           write(iout,'(5i4,f20.10)') m, n, l, ind_1, ind_2, int_value
          end do

        end do ! end loop over n_max
      end do ! end loop over n_max

    end do ! end loop over para%l

    call cpu_time(finish)
    write(iout,'(X,a,f10.5,X,a)') 'Time taken for 1e transformation = ', finish-start, 'seconds.'

  end subroutine Calc1eOrbInts

  subroutine Calc2eRadOrbInts_old()

    use DVRData, only : two_e_rad_int, para, grid, eigen_vecs

    integer  :: i, j, l, l1, l2, l3 ,l4, n_l, l_val, m, n, mp, np, error, ml, ind_1, ind_2
    real(dp) :: int_value, start, finish, int_value_xc, int_value_dr
    integer  :: count_i, count_j, count_l
    logical  :: split

    real(dp), allocatable :: inter_int(:,:,:,:,:)

    call cpu_time(start)

    n_l = para%l+1

    allocate(TwoERadOrbInts(orb%n_max,orb%n_max, orb%n_max, orb%n_max, n_l, n_l, n_l, n_l, 2*para%l+1), stat=error)
    call allocerror(error)
    allocate(inter_int(para%ng,orb%n_max,orb%n_max,n_l,n_l), stat=error)
    call allocerror(error)


    inter_int = zero
    TwoERadOrbInts = zero

    ! The transformation of 1e integrals is done in two steps
    ! i and j are basis indices, while m and n are orbital indices
    ! h_{ij} -> h_{mn} using transformation matrix b_{in}
    ! First step: h_{in} = \sum_j h_{ij} b_{in} 
    ! Second step: h_{mn} = \sum_i b^*_{im} h_{in} 

    ! The calculation is done over a loop of l

!   write(*,*) 'Size 1', size(eigen_vecs(:,1,1))
!   write(*,*) 'Size 2', size(eigen_vecs(1,:,1))
!   write(*,*) 'Size 3', size(eigen_vecs(1,1,:))

!   flush(6)

!   split = .false.
    split = .true.

    do l = 1, 2*para%l + 1
      l_val = l - 1

      if (split) then

      ! The first step is done here
      do m = 1, orb%n_max
        do n = 1, orb%n_max
          do l1 = 1, n_l
            do l2 = 1, n_l
              do i = 1, para%ng
       
                int_value = 0.0d0
                do j = 1, para%ng
                   int_value = int_value + two_e_rad_int(i,j,l)*eigen_vecs(j,n,l2)*eigen_vecs(j,m,l1)
                end do 
                inter_int(i,m,n,l1,l2) = int_value
!               if (l1.eq.l2.and.abs(int_value).gt.1e-12) write(87,'(4i3,f13.8)') i,m,n,l1,int_value
 !              write(76,'(3I5,X,F20.10)') i, n, l, eigen_vecs(i,n,l)
              end do
            end do 
          end do 
        end do
      end do ! end loop over n_max

      ! The second step is done here, still it is inside the loop of l

      do m = 1, orb%n_max
        do n = 1, orb%n_max
          do mp = 1, orb%n_max
            do np = 1, orb%n_max
              do l1 = 1, n_l
                do l2 = 1, n_l
                  do l3 = 1, n_l
                    do l4 = 1, n_l

                      int_value = 0.0d0
                      int_value_xc = 0.0d0
                      do i = 1, para%ng
                        int_value = int_value + eigen_vecs(i,mp,l1)*eigen_vecs(i,np,l3)*inter_int(i,m,n,l2,l4)
                      end do
          
!                     if(l1.eq.l4.and.l2.eq.l3) write(87,'(7i4,f16.8)') m, n , mp, np, l1, l2, l, int_value
          
                      TwoERadOrbInts(mp, m, np, n, l1, l2, l3, l4, l) = int_value
                    end do
                  end do
                end do
              end do ! end loop over n_max
            end do ! end loop over n_max
          end do
        end do ! end loop over n_max
      end do ! end loop over n_max

  !   else 

  !     do m = 1, orb%n_max
  !       do n = 1, orb%n_max
  !         do mp = 1, orb%n_max
  !           do np = 1, orb%n_max
  !             int_value = 0.0d0
  !             do i = 1, para%ng
  !               do j = 1, para%ng
  !                 int_value = int_value + (eigen_vecs(i,mp,l)*eigen_vecs(i,np,l))*two_e_rad_int(i,j,l)*(eigen_vecs(j,m,l)*eigen_vecs(j,n,l))
! !        write(80,'(4i4, 4f16.8)') m, n, i, j, eigen_vecs(i,m,l), eigen_vecs(j,n,l),two_e_rad_int(i,j,l), int_value
  !               end do 
  !             end do 
  !             TwoERadOrbInts(mp, m, np, n, l) = int_value
  !           write(78,'(5i4,f16.8)') mp, np, m, n, l, int_value
! !     write(82,'(2I4,ES25.17)') m, n, int_value
  !           end do ! end loop over n_max
  !         end do ! end loop over n_max
  !       end do ! end loop over n_max
  !     end do ! end loop over n_max

      end if

    end do ! end loop over para%l

    call cpu_time(finish)
    write(iout,'(X,a,f10.5,X,a)') 'Time taken for 2e transformation = ', finish-start, 'seconds.'


  end subroutine Calc2eRadOrbInts_old

  subroutine Calc2eRadOrbInts(EigVecs)

    use DVRData, only : two_e_rad_int, para, grid

    real(dp), allocatable, intent(in) :: EigVecs(:,:,:)

    integer  :: i, j, l, l1, l2, l3 ,l4, n_l, l_val, m, n, mp, np, error, ml, ind_1, ind_2
    real(dp) :: int_value, start, finish, int_value_xc, int_value_dr
    integer  :: count_i, count_j, count_l
    logical  :: split

    real(dp), allocatable :: inter_int(:,:,:,:,:)
    real(dp), allocatable :: inter_int_dr(:,:,:,:),inter_int_xc(:,:,:,:)

    call cpu_time(start)

    n_l = para%l+1

!   allocate(TwoERadOrbInts(orb%n_max,orb%n_max, orb%n_max, orb%n_max, n_l, n_l, n_l, n_l, 2*para%l+1), stat=error)
!   call allocerror(error)
    allocate(inter_int(para%ng,orb%n_max,orb%n_max,n_l,n_l), stat=error)
    call allocerror(error)

    ! Here the arrays for storng the 2e radial integrals are allocated. There are two separate arrays used for storing
    ! the direct and exchange integrals. Use of a single array would also store some unnecessary elements which
    ! are not required in the further part of the calculation.
    ! Direct integrals
    allocate(TwoERadOrbInts_dr(orb%n_max,orb%n_max, orb%n_max, orb%n_max, n_l, n_l, 2*para%l+1), stat=error)
    call allocerror(error)

    ! Exchange integrals
    allocate(TwoERadOrbInts_xc(orb%n_max,orb%n_max, orb%n_max, orb%n_max, n_l, n_l, 2*para%l+1), stat=error)
    call allocerror(error)

    ! Allocating arrays to store intermediate matrix product, direct and exchange part are separted. 
!   allocate(inter_int_dr(para%ng,orb%n_max,orb%n_max,n_l), stat=error)
!   call allocerror(error)

!   allocate(inter_int_xc(para%ng,orb%n_max,orb%n_max,n_l), stat=error)
!   call allocerror(error)

    inter_int = zero
    TwoERadOrbInts_dr = zero
    TwoERadOrbInts_xc = zero

    ! The transformation of 1e integrals is done in two steps
    ! i and j are basis indices, while m and n are orbital indices
    ! h_{ij} -> h_{mn} using transformation matrix b_{in}
    ! First step: h_{in} = \sum_j h_{ij} b_{in} 
    ! Second step: h_{mn} = \sum_i b^*_{im} h_{in} 

    ! The calculation is done over a loop of l

!   write(*,*) 'Size 1', size(EigVecs(:,1,1))
!   write(*,*) 'Size 2', size(EigVecs(1,:,1))
!   write(*,*) 'Size 3', size(EigVecs(1,1,:))

!   flush(6)

!   split = .false.
    split = .true.

    do l = 1, 2*para%l + 1
      l_val = l - 1

      if (split) then

      ! The first step is done here
      do m = 1, orb%n_max
        do l1 = 1,n_l
          do n = 1, orb%n_max
            do l2 = 1, n_l
              do i = 1, para%ng
                int_value = 0.0d0

                do j = 1, para%ng
                   int_value = int_value + two_e_rad_int(i,j,l)*EigVecs(j,n,l2)*EigVecs(j,m,l1)
                end do 

!               if (abs(int_value).gt.1e-12) write(88,'(4i3,f13.8)') i,m,n,l1,int_value
                inter_int(i,m,n,l1,l2) = int_value
 !              write(76,'(3I5,X,F20.10)') i, n, l, EigVecs(i,n,l)
              end do
            end do 
          end do 
        end do
      end do ! end loop over n_max

      ! The second step is done here, still it is inside the loop of l
      do m = 1, orb%n_max
          do n = 1, orb%n_max
              do mp = 1, orb%n_max
                do np = 1, orb%n_max
                  do l1 = 1, n_l
                    do l2 = 1, n_l

                      int_value = 0.0d0
                      int_value_xc = 0.0d0
                      do i = 1, para%ng
                        int_value = int_value + EigVecs(i,mp,l1)*EigVecs(i,np,l1)*inter_int(i,m,n,l2,l2)
                        int_value_xc = int_value_xc + EigVecs(i,mp,l1)*inter_int(i,m,np,l2,l1)*EigVecs(i,n,l2)
                      end do
          
!                     write(81,'(7i4,f16.8)') m, n, mp, np, l1, l2, l, int_value_xc
          
                      !TwoERadOrbInts(mp, m, np, n, l1, l2, l3, l4, l) = int_value
                      TwoERadOrbInts_dr(mp, m, np, n, l1, l2, l) = int_value
                      TwoERadOrbInts_xc(mp, m, np, n, l1, l2, l) = int_value_xc
                    end do
                  end do
                end do
              end do ! end loop over n_max
!           end do ! end loop over n_max
!         end do
        end do ! end loop over n_max
      end do ! end loop over n_max

      else 

        do mp = 1, orb%n_max
          do np = 1, orb%n_max
            do l1 = 1, n_l
              do m = 1, orb%n_max
                do n = 1, orb%n_max
                  do l2 = 1, n_l
                  int_value = 0.0d0
                  int_value_xc = 0.0d0
                    do i = 1, para%ng
                      do j = 1, para%ng
                        int_value = int_value + (EigVecs(i,mp,l1)*EigVecs(i,np,l1))*two_e_rad_int(i,j,l)*(EigVecs(j,m,l2)*EigVecs(j,n,l2))
                        int_value_xc = int_value_xc + two_e_rad_int(i,j,l)*(EigVecs(i,mp,l1)*EigVecs(j,m,l2))*(EigVecs(i,n,l2)*EigVecs(j,np,l1))
!          write(80,'(4i4, 4f16.8)') m, n, i, j, EigVecs(i,m,l), EigVecs(j,n,l),two_e_rad_int(i,j,l), int_value
                      end do
                    end do
                    TwoERadOrbInts_dr(mp, m, np, n, l1, l2, l) = int_value
                    TwoERadOrbInts_xc(mp, m, np, n, l1, l2, l) = int_value_xc
!                   write(80,'(7i3,f16.8)') mp, m, np, n, l1, l2, l, int_value
!                   write(81,'(7i3,f16.8)') mp, m, np, n, l1, l2, l, int_value_xc
                  end do 
                end do 
!             write(78,'(5i4,f16.8)') mp, np, m, n, l, int_value
!       write(82,'(2I4,ES25.17)') m, n, int_value
              end do ! end loop over n_max
            end do ! end loop over n_max
          end do ! end loop over n_max
        end do ! end loop over n_max

      end if

    end do ! end loop over para%l

    call cpu_time(finish)
    write(iout,'(X,a,f10.5,X,a)') 'Time taken for 2e transformation = ', finish-start, 'seconds.'

  end subroutine Calc2eRadOrbInts

  subroutine WriteInts(tol)
    
    use DVRData, only : para

    real(dp), intent(in) :: tol
    integer :: i, j, k, l, f_int, norbs, ij, kl, ijkl, i_n, j_n, k_n, l_n, nelec
    real(dp) :: h_core, int_value

    f_int = 15
    open(f_int, file=file_int, status='unknown', form="formatted")

    norbs = orb%nSpatialOrbs - nFrozen

    nelec = nint(para%z) - 2*nFrozen

    write(f_int,1001) norbs, nelec, 0

1001 format(' &FCI NORB=', i5, ',NELEC=', i3, ',MS2=', i3,',')

    write(f_int,1002, advance='no') 

1002 format('  ORBSYM=')
 
    do i = 1, norbs

      write(f_int, '(i1)', advance='no') 1

      if (i.lt.norbs) then
        write(f_int,1003, advance='no')
      else
        write(f_int,1004) 
      endif

    end do
    
1003 format(',')
1004 format(',')

    write(f_int,*) ' ISYM=1,'
    write(f_int, *) ' &END'

    ij  = 0
    ijkl = 0
    do i = 1, norbs
      i_n = i + nFrozen
      do j = 1, i
        j_n = j + nFrozen
        kl = 0
!       do k = 1, norbs
        do k = 1, i
          k_n = k + nFrozen
          do l = 1, k
            l_n = l + nFrozen
            if (ij.ge.kl) then
              if (abs(TwoEInts(i_n,k_n,j_n,l_n)).gt.tol) &
              & write(f_int, 1005) TwoEInts(i_n,k_n,j_n,l_n), i, j, k, l
              ijkl = ijkl + 1
            end if
            kl = kl + 1
          end do
        end do
        ij = ij + 1
      end do
    end do

!   ij  = 0
!   ijkl = 0
!   do i = 1, norbs
!     do j = 1, norbs
!       kl = 0
!       do k = 1, norbs
!         do l = 1, norbs
!             if (abs(TwoEInts(i,k,j,l)).gt.tol) &
!             & write(f_int, 1005) TwoEInts(i,k,j,l), i, j, k, l
!         end do
!       end do
!     end do
!   end do

    do i = 1, norbs
      i_n = i + nFrozen
      do j = 1, i
        j_n = j + nFrozen
        int_value = OneEInts(i_n,j_n)
!       if (nFrozen.gt.0.and.i.eq.j) then
        if (nFrozen.gt.0) then
          do k = 1, nfrozen
            int_value = int_value + 2.0d0*TwoEInts(i_n,k,j_n,k) - TwoEInts(i_n,k,k,j_n) 
          end do
        end if
        if (abs(int_value).gt.tol) &
!       if (i.eq.j) &
        & write(f_int, 1005) int_value, i, j, 0, 0
      end do 
    end do

    h_core = 0.0_dp
    if (nFrozen.gt.0) then
      do i = 1, nFrozen
        h_core = h_core + 2.0d0*OneEInts(i,i)
        do j = 1, nFrozen
          h_core = h_core + 2.0d0*TwoEInts(i,j,i,j) - TwoEInts(i,j,j,i)
        end do
      end do  
    end if
    write(f_int, 1005) h_core, 0, 0, 0, 0

1005 format(f20.16,x,5i5)


    close(f_int)
  end subroutine WriteInts

end module Orbints
