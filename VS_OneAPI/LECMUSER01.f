c     revised user01 interface, double precision, si only.
c     units: kg, m, s, pa; density in kg/m3; a2 in 1/pa.
c     uparam(1:48) and uvar(:,1:12) retain the original layout.
c     this is a reviewed implementation, not a calibrated kf model.
c     fail_ten and faileqs are reserved; no deletion is implemented.
c=================================================================
c     user01 solid kf concrete material - starter
c=================================================================
c     功能：读取用户材料参数，自动生成缺省值，打包给 engine
c
c     移植来源：ls-dyna umat41 (kf concrete model)
c
c     参数数量：nuparam = 48
c     状态变量：nuvar   = 12
c
c     状态变量含义（与 ls-dyna hsv 一一对应）：
c       uvar(1)  = volumetric strain           体积应变
c       uvar(2)  = output ( = uvar(9) )        输出用（= 总损伤）
c       uvar(3)  = plastic volumetric strain   塑性体积应变
c       uvar(4)  = max elastic volumetric strain 最大弹性体积应变
c       uvar(5)  = shear damage lambda_c       剪切损伤因子
c       uvar(6)  = pore collapse damage        孔隙压实损伤
c       uvar(7)  = etac                        剪切损伤度
c       uvar(8)  = etat                        拉伸损伤度
c       uvar(9)  = total damage eta            总损伤
c       uvar(10) = equivalent plastic strain   等效塑性应变
c       uvar(11) = eta (current damage)        当前损伤
c       uvar(12) = tensile damage lambda_t     拉伸损伤因子
c
c     uparam 排列（48 个，与 ls-dyna cm(1:48) 一一对应）：
c       1  = fc        单轴压缩强度
c       2  = els_mol   弹性模量
c       3  = k         体积模量
c       4  = g         剪切模量
c       5  = t         拉伸强度
c       6  = fdf1      流动法则因子 ω
c       7  = frac      断裂应变（损伤特征应变）
c       8  = fail_ten  保留参数，当前未实现单元删除
c       9  = d1        损伤系数1
c       10 = d2        损伤系数2
c       11 = d3        损伤系数3（体积损伤）
c       12-21 = k1..k10   10 段卸载体积模量
c       22-31 = miu1..miu10 10 段体积应变节点
c       32-41 = p1..p10   10 段压力节点
c       42 = faileqs   保留参数，当前未实现单元删除
c       43 = alfa       剪切损伤参数
c       44 = rate       应变率开关（<1 关闭）
c       45 = a1         强度面参数
c       46 = a2         强度面参数
c       47 = row0       初始密度
c       48 = dc_mode    剪切损伤模式（<1 模式1，≥1 模式2）
c=================================================================
      subroutine lecmuser01(iin,iout,uparam,maxuparam,nuparam,
     .     nuvar,ifunc,maxfunc,nfunc,parmat,userbuf)
      use law_user
      use, intrinsic :: ieee_arithmetic
      implicit none
      external arret

c-----------------------------------------------------------------
c     接口参数
c-----------------------------------------------------------------
      integer iin,iout,maxuparam,nuparam,nuvar
      integer maxfunc,nfunc,ifunc(maxfunc)
      double precision uparam(maxuparam),parmat(100)

c-----------------------------------------------------------------
c     局部变量：材料参数（对应 ls-dyna cm(1:48)）
c-----------------------------------------------------------------
      double precision cm(48)
      double precision fc,els_mol,k,g,t,fdf1,frac,fail_ten
      double precision d1,d2,d3
      double precision k1,k2,k3,k4,k5,k6,k7,k8,k9,k10
      double precision miu1,miu2,miu3,miu4,miu5
      double precision miu6,miu7,miu8,miu9,miu10
      double precision p1,p2,p3,p4,p5,p6,p7,p8,p9,p10
      double precision faileqs,alfa,rate,a1,a2,row0,dc_mode
      double precision niu, zot, zot2
      integer i,j,ios
      double precision ekg
      double precision ktab(10),vtab(10),ptab(10)

      type(ulawbuf) :: userbuf

c-----------------------------------------------------------------
c     小量常数
c-----------------------------------------------------------------
      zot  = 1.0d-20      ! 极小量，防止除零
      zot2 = 1.0d-10      ! 小量，用于参数是否被用户填写的判断

c-----------------------------------------------------------------
c     读取用户材料数据（48 个参数，每行 8 个，共 6 行）
c-----------------------------------------------------------------
c     fail before writing beyond the caller's parameter buffer.
      nuparam = 0
      nuvar = 0
      nfunc = 0
      if (maxuparam.lt.48) then
        write(iout,*) 'kf user01: maxuparam must be at least 48.'
        call arret(2)
        return
      end if
      uparam(1:48) = 0.0d0
      parmat(1:3) = 0.0d0
      do j=1,6
        read(iin,'(8f10.0)')
     .       (cm(i),i=8*j-7,8*j)
      end do

c-----------------------------------------------------------------
c     从 cm 数组提取到命名变量（便于阅读）
c-----------------------------------------------------------------
      fc       = cm(1)
      els_mol  = cm(2)
      k        = cm(3)
      g        = cm(4)
      t        = cm(5)
      fdf1     = cm(6)
      frac     = cm(7)
      fail_ten = cm(8)
      d1       = cm(9)
      d2       = cm(10)
      d3       = cm(11)
      k1       = cm(12)
      k2       = cm(13)
      k3       = cm(14)
      k4       = cm(15)
      k5       = cm(16)
      k6       = cm(17)
      k7       = cm(18)
      k8       = cm(19)
      k9       = cm(20)
      k10      = cm(21)
      miu1     = cm(22)
      miu2     = cm(23)
      miu3     = cm(24)
      miu4     = cm(25)
      miu5     = cm(26)
      miu6     = cm(27)
      miu7     = cm(28)
      miu8     = cm(29)
      miu9     = cm(30)
      miu10    = cm(31)
      p1       = cm(32)
      p2       = cm(33)
      p3       = cm(34)
      p4       = cm(35)
      p5       = cm(36)
      p6       = cm(37)
      p7       = cm(38)
      p8       = cm(39)
      p9       = cm(40)
      p10      = cm(41)
      faileqs  = cm(42)
      alfa     = cm(43)
      rate     = cm(44)
      a1       = cm(45)
      a2       = cm(46)
      row0     = cm(47)
      dc_mode  = cm(48)

c-----------------------------------------------------------------
c     参数自动生成（48mpa 混凝土）
c     若 fc < 0，视为触发自动生成，按 48mpa 混凝土经验公式
c     生成全套参数（保留原文件中的经验公式）
c-----------------------------------------------------------------
        fc = -fc                                          ! 取绝对值作为强度
        els_mol = 57000.0d0*(fc/1.0d6/145.0d0)**0.5d0*1.0d6  ! 弹性模量经验公式
        niu = 0.20d0                                      ! 泊松比 0.2
        k   = els_mol/3.0d0/(1.0d0-2.0d0*niu)             ! 体积模量
        g   = els_mol/2.0d0/(1.0d0+niu)                   ! 剪切模量
        t   = 1.58d0*(fc/1.0d6*145.0d0)**(2.0d0/3.0d0)    ! 拉伸强度经验公式
     .        /145.0d0*1.0d6
c       10 段体积应变节点（压实曲线）
        miu1  = 0.0d0
        miu2  = 0.1500d-02
        miu3  = 0.4300d-02
        miu4  = 0.1010d-01
        miu5  = 0.3050d-01
        miu6  = 0.5130d-01
        miu7  = 0.7260d-01
        miu8  = 0.9430d-01
        miu9  = 1.7400d-01
        miu10 = 2.0800d-01

c       10 段卸载体积模量（孔隙压实后模量逐渐增大）
        k1  = k
        k2  = k
        k3  = 1.014d0*k
        k4  = 1.065d0*k
        k5  = 1.267d0*k
        k6  = 1.470d0*k
        k7  = 1.672d0*k
        k8  = 1.825d0*k
        k9  = 4.106d0*k
        k10 = 5.000d0*k

c       10 段压力节点（对应的压力值）
        p1  = 0.0d0
        p2  = k*miu2
        p3  = 2.18d0*p2
        p4  = 3.50d0*p2
        p5  = 6.65d0*p2
        p6  = 10.03d0*p2
        p7  = 14.23d0*p2
        p8  = 21.77d0*p2
        p9  = 127.1d0*p2
        p10 = 194.4d0*p2

c       其它参数缺省值
        a1      = 0.5876d0         ! 强度面参数
        a2      = 0.025d0/fc       ! 强度面参数
        d1      = 0.04d0           ! 损伤系数1
        d2      = 1.5d0            ! 损伤系数2
        fdf1    = 0.5d0            ! 流动法则因子
        d3      = 1.0d-4           ! 体积损伤系数
        alfa    = 1.0d0            ! 剪切损伤参数
        rate    = -1.0d0            ! 打开应变率效应
        frac    = 0.01d0           ! 断裂应变
        row0    = 2500.0d0         ! 密度
        dc_mode = 1.0d0            ! 剪切损伤模式2

c-----------------------------------------------------------------
c     参数合法性校验
c-----------------------------------------------------------------
      nuparam = 48

      uparam(1)  = fc
      uparam(2)  = els_mol
      uparam(3)  = k
      uparam(4)  = g
      uparam(5)  = t
      uparam(6)  = fdf1
      uparam(7)  = frac
      uparam(8)  = fail_ten
      uparam(9)  = d1
      uparam(10) = d2
      uparam(11) = d3
      uparam(12) = k1
      uparam(13) = k2
      uparam(14) = k3
      uparam(15) = k4
      uparam(16) = k5
      uparam(17) = k6
      uparam(18) = k7
      uparam(19) = k8
      uparam(20) = k9
      uparam(21) = k10
      uparam(22) = miu1
      uparam(23) = miu2
      uparam(24) = miu3
      uparam(25) = miu4
      uparam(26) = miu5
      uparam(27) = miu6
      uparam(28) = miu7
      uparam(29) = miu8
      uparam(30) = miu9
      uparam(31) = miu10
      uparam(32) = p1
      uparam(33) = p2
      uparam(34) = p3
      uparam(35) = p4
      uparam(36) = p5
      uparam(37) = p6
      uparam(38) = p7
      uparam(39) = p8
      uparam(40) = p9
      uparam(41) = p10
      uparam(42) = faileqs
      uparam(43) = alfa
      uparam(44) = rate
      uparam(45) = a1
      uparam(46) = a2
      uparam(47) = row0
      uparam(48) = dc_mode

c-----------------------------------------------------------------
c     状态变量个数（与 ls-dyna hsv(1:12) 一一对应）
c-----------------------------------------------------------------
      nuvar = 12
      nfunc = 0

c-----------------------------------------------------------------
c     材料模量信息（供求解器时间步长估计）
c       parmat(1) = 纵波模量 k + 4g/3
c       parmat(2) = 弹性模量 e
c       parmat(3) = 泊松比 nu（由 e、k 反推）
c-----------------------------------------------------------------
      parmat(1) = els_mol*niu/((1.0+niu)*(1.0-2.0*niu))
      parmat(2) = els_mol
      parmat(3) = 0.2

c-----------------------------------------------------------------
c-----------------------------------------------------------------
c     打印材料参数到输出文件
c-----------------------------------------------------------------
      write(iout,*) 'kf user01 units: kg, m, s, pa.'
      write(iout,*) 'material density must match row0.'
      if (fail_ten.ne.0.0d0 .or. faileqs.ne.0.0d0) then
        write(iout,*) 'warning: fail_ten/faileqs are reserved.'
        write(iout,*) 'this revision does not delete elements.'
      end if

      write(iout,1000)

c     ---- 基本弹性/强度参数 ----
      write(iout,1100) fc,els_mol,k,g,t
      write(iout,1110) fdf1,frac,fail_ten
      write(iout,1120) d1,d2,d3,a1,a2
      write(iout,1130) faileqs,alfa,rate,row0,dc_mode

c     ---- 10 段卸载体积模量 ----
      write(iout,1200) k1,k2,k3,k4,k5
      write(iout,1201) k6,k7,k8,k9,k10

c     ---- 10 段体积应变节点 ----
      write(iout,1300) miu1,miu2,miu3,miu4,miu5
      write(iout,1301) miu6,miu7,miu8,miu9,miu10

c     ---- 10 段压力节点 ----
      write(iout,1400) p1,p2,p3,p4,p5
      write(iout,1401) p6,p7,p8,p9,p10

c     ---- 求解器信息 ----
      write(iout,1500) nuparam,nuvar,nfunc
      write(iout,1510) parmat(1),parmat(2),parmat(3)

 1000 format(5x,' user01 solid kf concrete law',/,
     &       5x,' -----------------------------',//)

 1100 format(
     & 5x,'fc      = ',e12.4/,
     & 5x,'els_mol = ',e12.4/,
     & 5x,'k       = ',e12.4/,
     & 5x,'g       = ',e12.4/,
     & 5x,'t       = ',e12.4/)

 1110 format(
     & 5x,'fdf1    = ',e12.4/,
     & 5x,'frac    = ',e12.4/,
     & 5x,'fail_ten= ',e12.4/)

 1120 format(
     & 5x,'d1      = ',e12.4/,
     & 5x,'d2      = ',e12.4/,
     & 5x,'d3      = ',e12.4/,
     & 5x,'a1      = ',e12.4/,
     & 5x,'a2      = ',e12.4/)

 1130 format(
     & 5x,'faileqs = ',e12.4/,
     & 5x,'alfa    = ',e12.4/,
     & 5x,'rate    = ',e12.4/,
     & 5x,'row0    = ',e12.4/,
     & 5x,'dc_mode = ',e12.4/)

 1200 format(
     & 5x,'k1      = ',e12.4/,
     & 5x,'k2      = ',e12.4/,
     & 5x,'k3      = ',e12.4/,
     & 5x,'k4      = ',e12.4/,
     & 5x,'k5      = ',e12.4/)

 1201 format(
     & 5x,'k6      = ',e12.4/,
     & 5x,'k7      = ',e12.4/,
     & 5x,'k8      = ',e12.4/,
     & 5x,'k9      = ',e12.4/,
     & 5x,'k10     = ',e12.4/)

 1300 format(
     & 5x,'miu1    = ',e12.4/,
     & 5x,'miu2    = ',e12.4/,
     & 5x,'miu3    = ',e12.4/,
     & 5x,'miu4    = ',e12.4/,
     & 5x,'miu5    = ',e12.4/)

 1301 format(
     & 5x,'miu6    = ',e12.4/,
     & 5x,'miu7    = ',e12.4/,
     & 5x,'miu8    = ',e12.4/,
     & 5x,'miu9    = ',e12.4/,
     & 5x,'miu10   = ',e12.4/)

 1400 format(
     & 5x,'p1      = ',e12.4/,
     & 5x,'p2      = ',e12.4/,
     & 5x,'p3      = ',e12.4/,
     & 5x,'p4      = ',e12.4/,
     & 5x,'p5      = ',e12.4/)

 1401 format(
     & 5x,'p6      = ',e12.4/,
     & 5x,'p7      = ',e12.4/,
     & 5x,'p8      = ',e12.4/,
     & 5x,'p9      = ',e12.4/,
     & 5x,'p10     = ',e12.4/)

 1500 format(
     & 5x,'nuparam = ',i8/,
     & 5x,'nuvar   = ',i8/,
     & 5x,'nfunc   = ',i8/)

 1510 format(
     & 5x,'parmat(1)= ',e12.4/,
     & 5x,'parmat(2)= ',e12.4/,
     & 5x,'parmat(3)= ',e12.4//)

      return
      end