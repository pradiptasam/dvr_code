module OrbInts

  use constants
  use util_mod, only : stop_all, allocerror
  use ReadInput, only : n_max
  use OrbData
  use CombineInts, only : CombineOrbInts

  implicit none

  contains

  subroutine SetOrbData()

    use DVRData, only : para
    use util_mod, only : allocerror

    integer :: i, j, k, l_val, i_o, indx, error

    orb%n_max = n_max 

    allocate(SpatialOrbInd(n_max,para%l+1,2*para%l+1),stat=error)
    call allocerror(error)

    SpatialOrbInd = 0

    indx = 0
    do i = 1, n_max
      l_val = min(i,para%l+1)
!     write(*,*) 'limit for l_val:', l_val
      do j = 1, l_val
        do k = 1, 2*j-1
          indx = indx + 1
          SpatialOrbInd(i-j+1,j,k) = indx
          write(iout, *) i-j+1, j, k, SpatialOrbInd(i-j+1, j, k)
        end do
      end do
    end do
      
    orb%nSpatialOrbs = indx


    write(iout, *) '**********'
    write(iout, *) 'Setting up these parameters for the orbitals:'
    write(iout, '(X,A,3X, I6)') 'orb%n_max     =', n_max
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

  call SetOrbData()

  call Calc1eOrbInts()

  call Calc2eRadOrbInts()

  call CombineOrbInts()

  end subroutine GetOrbInts
! ***********************


  subroutine Calc1eOrbInts()

    use DVRData, only : one_e_rad_int, para, grid, eigen_vecs

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
      l_val = l - 1

      ! The first step is done here
      do n = 1, orb%n_max - (l-1)
        do i = 1, para%ng

          int_value = 0.0d0
          do j = 1, para%ng
             int_value = int_value + one_e_rad_int(i,j,l)*eigen_vecs(j,n,l)
          end do 
          inter_int(i,n) = int_value
!         write(iout,*) i, n, l, int_value
        end do 
      end do ! end loop over n_max

      ! The second step is done here, still it is inside the loop of l
      do m = 1, orb%n_max - (l-1)
        do n = 1, orb%n_max - (l-1)

          int_value = 0.0d0
          do i = 1, para%ng
            int_value = int_value + eigen_vecs(i,m,l) * inter_int(i,n)
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
!           write(76,*) ind_1, ind_2, int_value
          end do

        end do ! end loop over n_max
      end do ! end loop over n_max

    end do ! end loop over para%l

    call cpu_time(finish)
    write(iout,'(X,a,f10.5,X,a)') 'Time taken for 1e transformation = ', finish-start, 'seconds.'

  end subroutine Calc1eOrbInts

  subroutine Calc2eRadOrbInts()

    use DVRData, only : two_e_rad_int, para, grid, eigen_vecs

    integer  :: i, j, l, l_val, m, n, error, ml, ind_1, ind_2
    real(dp) :: int_value, start, finish
    integer  :: count_i, count_j, count_l

    real(dp), allocatable :: inter_int(:,:)

    call cpu_time(start)

    allocate(inter_int(para%ng,orb%n_max), stat=error)
    call allocerror(error)

    allocate(TwoERadOrbInts(orb%n_max,orb%n_max, 2*para%l+1), stat=error)
    call allocerror(error)

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

   flush(6)


    do l = 1, 2*para%l + 1
      l_val = l - 1

      ! The first step is done here
      do n = 1, orb%n_max
        do i = 1, para%ng

          int_value = 0.0d0
          do j = 1, para%ng
             int_value = int_value + two_e_rad_int(i,j,l)*eigen_vecs(j,n,l)
          end do 
          inter_int(i,n) = int_value
!         write(76,'(3I5,X,F20.10)') i, n, l, eigen_vecs(i,n,l)
        end do 
      flush(6)
      end do ! end loop over n_max

      ! The second step is done here, still it is inside the loop of l
      do m = 1, orb%n_max
        do n = 1, orb%n_max

          int_value = 0.0d0
          do i = 1, para%ng
            int_value = int_value + eigen_vecs(i,m,l) * inter_int(i,n)
          end do

          write(76,*) m, n, l, int_value

          TwoERadOrbInts(m, n, l) = int_value

        end do ! end loop over n_max
      end do ! end loop over n_max

    end do ! end loop over para%l

    call cpu_time(finish)
    write(iout,'(X,a,f10.5,X,a)') 'Time taken for 2e transformation = ', finish-start, 'seconds.'

  end subroutine Calc2eRadOrbInts

end module Orbints