c     revised user01 interface, double precision, si only.
c     units: kg, m, s, pa; density in kg/m3; a2 in 1/pa.
c     uparam(1:48) and uvar(:,1:12) retain the original layout.
c     this is a reviewed implementation, not a calibrated kf model.
c     fail_ten and faileqs are reserved; no deletion is implemented.
c=================================================================
c     user01 solid kf concrete material - engine
c=================================================================
c     功能：对 nel 个单元批量执行 kf 混凝土本构更新
c
c     移植来源：ls-dyna umat41
c
c     本构特征：
c       - 3d 各向同性弹性 + 径向返回 j2 塑性
c       - lode 角相关双强度面（fcmin / fcmax）
c       - 拉伸损伤 etat / 剪切损伤 etac / 体积损伤 三种机制
c       - 10 段分段状态方程（孔隙压实）
c       - 应变率强化（dift / difc）
c
c     状态变量（uvar(i,1..12)，对应 ls-dyna hsv(1..12)）：
c       uvar(i,1)  = volumetric strain             体积应变
c       uvar(i,2)  = output ( = uvar(i,9) )        输出用
c       uvar(i,3)  = plastic volumetric strain     塑性体积应变
c       uvar(i,4)  = max elastic volumetric strain 最大弹性体积应变
c       uvar(i,5)  = shear damage lambda_c         剪切损伤因子
c       uvar(i,6)  = pore collapse damage          孔隙压实损伤
c       uvar(i,7)  = etac                          剪切损伤度
c       uvar(i,8)  = etat                          拉伸损伤度
c       uvar(i,9)  = total damage eta              总损伤
c       uvar(i,10) = equivalent plastic strain     等效塑性应变
c       uvar(i,11) = eta (current damage)          当前损伤
c       uvar(i,12) = tensile damage lambda_t       拉伸损伤因子
c
c     注意：
c       - 未实现本构内部的单元删除，仅更新应力及历史变量
c       - 剪切应变增量按工程剪应变处理（/2 转张量剪应变）
c       - 逐元素写入 userbuf，避免 intel error #6366
c=================================================================
      subroutine luser01(
     1 nel,nuparam,nuvar,nfunc,ifunc,npf,
     2 tf,time,timestep,uparam,rho,volume,
     3 eint,ngl,soundsp,viscmax,uvar,off,
     4 sigy,pla,userbuf)
      use law_userso
      use, intrinsic :: ieee_arithmetic
      implicit none
      external arret

c-----------------------------------------------------------------
c     接口参数
c-----------------------------------------------------------------
      integer nel,nuparam,nuvar,nfunc,ngl(nel)
      integer ifunc(*),npf(*)
      double precision tf(*),time,timestep
      double precision uparam(nuparam),rho(nel),volume(nel)
      double precision eint(nel)
      double precision soundsp(nel),viscmax(nel)
      double precision uvar(nel,nuvar),off(nel)
      double precision sigy(nel),pla(nel)
      type(ulawintbuf) :: userbuf

      integer i,j

c-----------------------------------------------------------------
c     材料参数（从 uparam 提取）
c-----------------------------------------------------------------
      double precision fc,els_mol,k,g,t,fdf1,frac,fail_ten
      double precision d1,d2,d3
      double precision k1,k2,k3,k4,k5,k6,k7,k8,k9,k10
      double precision miu1,miu2,miu3,miu4,miu5
      double precision miu6,miu7,miu8,miu9,miu10
      double precision p1,p2,p3,p4,p5,p6,p7,p8,p9,p10
      double precision faileqs,alfa,rate,a1,a2,row0,dc_mode

c-----------------------------------------------------------------
c     局部工作变量
c-----------------------------------------------------------------
c     应力/应变
      double precision s(6),sigemaold(6),dstraininc(6)
      double precision st(6),sold(6)
c     压力相关
      double precision p,pcutoff,pnocut,rpcutoff
      double precision kav,kl,dmiu,dvvolel,volel,volele
      double precision bulkmod,kwave,rhowave,epold
c     lode 角相关
      double precision sita,fai,j2old,j3old,rp,kh,rat,ratden
      double precision dfaidp
      double precision cywh,tpsim1,ompsi2,sq,zj2
c     强度面/损伤
      double precision sigemaetr,j2
      double precision sigemay0
      double precision eta,eta_prime,etat,etac
      double precision etat_prime,etac_prime
      double precision lamuda_t,lamuda_c
      double precision fcmin,dfcndp,fcmax,dfcmdp
      double precision dmunum,drsdg,drsdh,drsdpsi,drdpsi
      double precision hosig,dydlam,dydp,fdf
      double precision denom,dmux,dpp
      double precision sscale,r3g,term3,dlambda,ff,fact
c     应变率
      double precision dp,ybl,dift,difc,dif
c     小量/常数
      double precision zot,zot2,seps,zot4
      double precision miul
      double precision zero,one,two,three,half

      data zero/0.0d0/,one/1.0d0/,two/2.0d0/,
     .     three/3.0d0/,half/0.5d0/

c-----------------------------------------------------------------
c     小量常数
c-----------------------------------------------------------------
      zot  = 1.0d-20        ! 极小量
      zot2 = 1.0d-10        ! 小量（判断依据）
      zot4 = 1.0d-6         ! 拉伸压力截断的相对下限

c-----------------------------------------------------------------
c     从 uparam 提取材料参数
c-----------------------------------------------------------------
      fc       = uparam(1)
      els_mol  = uparam(2)
      k        = uparam(3)
      g        = uparam(4)
      t        = uparam(5)
      fdf1     = uparam(6)
      frac     = uparam(7)
      fail_ten = uparam(8)
      d1       = uparam(9)
      d2       = uparam(10)
      d3       = uparam(11)
      k1       = uparam(12)
      k2       = uparam(13)
      k3       = uparam(14)
      k4       = uparam(15)
      k5       = uparam(16)
      k6       = uparam(17)
      k7       = uparam(18)
      k8       = uparam(19)
      k9       = uparam(20)
      k10      = uparam(21)
      miu1     = uparam(22)
      miu2     = uparam(23)
      miu3     = uparam(24)
      miu4     = uparam(25)
      miu5     = uparam(26)
      miu6     = uparam(27)
      miu7     = uparam(28)
      miu8     = uparam(29)
      miu9     = uparam(30)
      miu10    = uparam(31)
      p1       = uparam(32)
      p2       = uparam(33)
      p3       = uparam(34)
      p4       = uparam(35)
      p5       = uparam(36)
      p6       = uparam(37)
      p7       = uparam(38)
      p8       = uparam(39)
      p9       = uparam(40)
      p10      = uparam(41)
      faileqs  = uparam(42)
      alfa     = uparam(43)
      rate     = uparam(44)
      a1       = uparam(45)
      a2       = uparam(46)
      row0     = uparam(47)
      dc_mode  = uparam(48)

c     依据 k 重新计算 seps（保证与当前 k 一致）
      seps = zot2*k
c     conservative eos stiffness bound, including all table slopes.
      kwave = k

c=================================================================
c     循环：对每个单元独立更新
c=================================================================
      do i=1,nel

c       deleted points remain inactive and return initialized outputs.
          userbuf%signxx(i)=zero
          userbuf%signyy(i)=zero
          userbuf%signzz(i)=zero
          userbuf%signxy(i)=zero
          userbuf%signyz(i)=zero
          userbuf%signzx(i)=zero
          userbuf%sigvxx(i)=zero
          userbuf%sigvyy(i)=zero
          userbuf%sigvzz(i)=zero
          userbuf%sigvxy(i)=zero
          userbuf%sigvyz(i)=zero
          userbuf%sigvzx(i)=zero
          userbuf%dpla(i)=zero
          pla(i)=zero
          sigy(i)=zero
          soundsp(i)=zero
          viscmax(i)=zero

c-----------------------------------------------------------------
c     1. 读取旧应力（从 userbuf）
c-----------------------------------------------------------------
        sigemaold(1) = userbuf%sigoxx(i)
        sigemaold(2) = userbuf%sigoyy(i)
        sigemaold(3) = userbuf%sigozz(i)
        sigemaold(4) = userbuf%sigoxy(i)
        sigemaold(5) = userbuf%sigoyz(i)
        sigemaold(6) = userbuf%sigozx(i)

c       旧应力偏量
        sold(1:3) = sigemaold(1:3)
     .            - sum(sigemaold(1:3))/three
        sold(4:6) = sigemaold(4:6)


c-----------------------------------------------------------------
c     2. 读取应变增量（从 userbuf）
c        剪切分量为工程剪应变增量，需 /2 转张量剪应变
c-----------------------------------------------------------------
        dstraininc(1) = userbuf%depsxx(i)
        dstraininc(2) = userbuf%depsyy(i)
        dstraininc(3) = userbuf%depszz(i)
        dstraininc(4) = userbuf%depsxy(i)*half
        dstraininc(5) = userbuf%depsyz(i)*half
        dstraininc(6) = userbuf%depszx(i)*half

c       应变增量偏量（正应力部分）
        dstraininc(1:3) = dstraininc(1:3)
     .                  - sum(dstraininc(1:3))/three

c-----------------------------------------------------------------
c     3. 初始步：状态变量清零
c-----------------------------------------------------------------
        if (time.eq.zero) then
          uvar(i,1)  = zero
          uvar(i,2)  = zero
          uvar(i,3)  = zero
          uvar(i,4)  = zero
          uvar(i,5)  = zero
          uvar(i,6)  = zero
          uvar(i,7)  = zero
          uvar(i,8)  = zero
          uvar(i,9)  = zero
          uvar(i,10) = zero
          uvar(i,11) = zero
          uvar(i,12) = zero
        end if

c-----------------------------------------------------------------
c     4. 读取历史损伤变量
c-----------------------------------------------------------------
        epold = uvar(i,10)
        lamuda_t = uvar(i,12)      ! 拉伸损伤因子
        lamuda_c = uvar(i,5)       ! 剪切损伤因子

c-----------------------------------------------------------------
c     5. 计算拉伸损伤 etat 及其对 lamuda_t 的导数
c        etat = 1 - [(1+(3λt/frac)^3)*exp(-6.93λt/frac)
c                    - λt/frac*(1+27)*exp(-6.93)]
c-----------------------------------------------------------------
        etat = one - ((one + (three*lamuda_t/frac)**3)
     .       * exp(-6.93d0*lamuda_t/frac)
     .       - lamuda_t/frac*(one+27.0d0)*exp(-6.93d0))
        etat_prime = -81.0d0*(lamuda_t/frac)**2
     .       * exp(-6.93d0*lamuda_t/frac)/frac
     .       + (6.93d0*(one+27.0d0*(lamuda_t/frac)**3))
     .       * exp(-6.93d0*lamuda_t/frac)/frac
     .       + 0.02738402432d0/frac

c-----------------------------------------------------------------
c     6. 计算剪切损伤 etac 及其对 lamuda_c 的导数
c        两种模式（dc_mode < 1 或 ≥ 1）
c-----------------------------------------------------------------
        if (dc_mode.lt.one) then
          etac = alfa*lamuda_c/(lamuda_c+one)
          etac_prime = alfa/(lamuda_c+one)**2
        else
          etac = lamuda_c/(alfa*lamuda_c+one)
          etac_prime = one/(alfa*lamuda_c+one)**2
        end if

c       损伤演化不可逆：取历史最大值，并限制在 [0, 0.9999]
        etac = max(etac, uvar(i,7))
        etac = min(etac, 0.9999d0)
        etac = max(etac, zero)

        etat = max(etat, uvar(i,8))
        etat = min(etat, 0.9999d0)
        etat = max(etat, zero)

c-----------------------------------------------------------------
c     7. 压力截断（rpcutoff）
c        未发生拉伸损伤：-t
c        已发生拉伸损伤：min(-t*zot4, -t*(1-eta))
c-----------------------------------------------------------------
        if (uvar(i,12).le.zot) then
          rpcutoff = -t
        else
          rpcutoff = min(-t*zot4, -t*(one-uvar(i,11)))
        end if

c-----------------------------------------------------------------
c     8. 应变率计算与 dif（动态强度增强因子）
c        ybl = 等效应变率
c        dift = 拉伸增强因子
c        difc = 压缩增强因子
c-----------------------------------------------------------------
        dp = sqrt((userbuf%depsxx(i)**2
     .           + userbuf%depsyy(i)**2
     .           + userbuf%depszz(i)**2
     .           + half*(userbuf%depsxy(i)**2
     .                 + userbuf%depsyz(i)**2
     .                 + userbuf%depszx(i)**2))*two/three)
        ybl = dp/max(timestep, zot)

        dift = (tanh((log10(max(ybl,1.0d-6))-1.6d0)*0.8d0)
     .         *(10.0d0/5.5d0-one)+one)*5.5d0
        dift = max(one, dift)
        difc = (dift-one)*t/fc + one

c       若 rate < 1，关闭应变率效应
        if (rate.lt.one) then
          dift = one
          difc = one
        end if

        pcutoff = rpcutoff*dift

c-----------------------------------------------------------------
c     9. 更新压力（10 段分段 eos）
c        hsv(1) 体积应变累积
c        hsv(4) 历史最大弹性体积应变
c        dvolel 卸载量
c-----------------------------------------------------------------
        dmiu = userbuf%depsxx(i)
     .       + userbuf%depsyy(i)
     .       + userbuf%depszz(i)
        uvar(i,1) = uvar(i,1) - dmiu       ! 压缩为正，体积应变累加

        volel  = uvar(i,1)
        volele = volel + uvar(i,3)
        uvar(i,4) = max(uvar(i,4), volele)
        dvvolel = volele - uvar(i,4)

c       10 段线性插值，得到 p、kav（当前模量）、kl（切线模量）
        if (uvar(i,4).lt.miu1) then
          p = p1
          kav = k1
          kl = zero
        else if (uvar(i,4).lt.miu2) then
          p = p1 + (uvar(i,4)-miu1)/(miu2-miu1)*p2
          kav = k1
          kl = (p2-p1)/(miu2-miu1)
        else if (uvar(i,4).lt.miu3) then
          p = p2 + (uvar(i,4)-miu2)/(miu3-miu2)*(p3-p2)
          kav = k2 + (uvar(i,4)-miu2)/(miu3-miu2)*(k3-k2)
          kl = (p3-p2)/(miu3-miu2)
        else if (uvar(i,4).lt.miu4) then
          p = p3 + (uvar(i,4)-miu3)/(miu4-miu3)*(p4-p3)
          kav = k3 + (uvar(i,4)-miu3)/(miu4-miu3)*(k4-k3)
          kl = (p4-p3)/(miu4-miu3)
        else if (uvar(i,4).lt.miu5) then
          p = p4 + (uvar(i,4)-miu4)/(miu5-miu4)*(p5-p4)
          kav = k4 + (uvar(i,4)-miu4)/(miu5-miu4)*(k5-k4)
          kl = (p5-p4)/(miu5-miu4)
        else if (uvar(i,4).lt.miu6) then
          p = p5 + (uvar(i,4)-miu5)/(miu6-miu5)*(p6-p5)
          kav = k5 + (uvar(i,4)-miu5)/(miu6-miu5)*(k6-k5)
          kl = (p6-p5)/(miu6-miu5)
        else if (uvar(i,4).lt.miu7) then
          p = p6 + (uvar(i,4)-miu6)/(miu7-miu6)*(p7-p6)
          kav = k6 + (uvar(i,4)-miu6)/(miu7-miu6)*(k7-k6)
          kl = (p7-p6)/(miu7-miu6)
        else if (uvar(i,4).lt.miu8) then
          p = p7 + (uvar(i,4)-miu7)/(miu8-miu7)*(p8-p7)
          kav = k7 + (uvar(i,4)-miu7)/(miu8-miu7)*(k8-k7)
          kl = (p8-p7)/(miu8-miu7)
        else if (uvar(i,4).lt.miu9) then
          p = p8 + (uvar(i,4)-miu8)/(miu9-miu8)*(p9-p8)
          kav = k8 + (uvar(i,4)-miu8)/(miu9-miu8)*(k9-k8)
          kl = (p9-p8)/(miu9-miu8)
        else if (uvar(i,4).lt.miu10) then
          p = p9 + (uvar(i,4)-miu9)/(miu10-miu9)*(p10-p9)
          kav = k9 + (uvar(i,4)-miu9)/(miu10-miu9)*(k10-k9)
          kl = (p10-p9)/(miu10-miu9)
        else
          p = p10 + (uvar(i,4)-miu10)/(miu10-miu9)*(p10-p9)
          kav = k10 + (uvar(i,4)-miu10)/(miu10-miu9)*(k10-k9)
          kl = (p10-p9)/(miu10-miu9)
        end if
        

c       卸载修正：卸载时用 kav 跟随
        if (dvvolel.lt.zero) then
          p = p + kav*dvvolel
        end if

        pnocut = p                 ! 截断前压力
        p = max(p, pcutoff)        ! 施加压力截断

c-----------------------------------------------------------------
c     10. 计算当前加载/卸载支路的 bulkmod
c-----------------------------------------------------------------
c       match the actual loading/unloading pressure branch above.
c       the original kp expression was unused and could overflow.
        if (dvvolel.lt.-zot4) then
          bulkmod = kav
        else
          bulkmod = kl
        end if

c-----------------------------------------------------------------
c     11. 根据压力计算 dif 和 rp（径向压力）
c-----------------------------------------------------------------
        if (p.lt.-t/three*dift) then
          dif = dift
        else if (p.lt.fc/three*difc) then
          dif = dift + (p+dift*t/three)
     .        /(one/three*(t*dift+fc*difc))*(difc-dift)
        else
          dif = difc
        end if

        rp = p/dif
        rp = max(-t, rp)

c-----------------------------------------------------------------
c     12. 组合损伤 eta
c        rp <= 0（拉伸）：eta = 1-(1-etac)(1-etat)
c        rp >  0（压缩）：eta = etac
c-----------------------------------------------------------------
        if (rp.le.zero) then
          eta = one - (one-etac)*(one-etat)
          eta = min(eta, 0.9999d0)
          eta = max(eta, zero)
          eta_prime = etat_prime - etac*etat_prime
        else
          eta = etac
          eta = min(eta, 0.9999d0)
          eta = max(eta, zero)
          eta_prime = etac_prime
        end if

        if (eta.ge.0.9999d0) eta_prime = zero

c-----------------------------------------------------------------
c     13. 试算偏应力（弹性预测）
c-----------------------------------------------------------------
        st(1) = two*g*dstraininc(1) + sold(1)
        st(2) = two*g*dstraininc(2) + sold(2)
        st(3) = two*g*dstraininc(3) + sold(3)
        st(4) = two*g*dstraininc(4) + sold(4)
        st(5) = two*g*dstraininc(5) + sold(5)
        st(6) = two*g*dstraininc(6) + sold(6)

        j2 = half*(st(1)**2+st(2)**2+st(3)**2)
     .     + st(4)**2 + st(5)**2 + st(6)**2
        sigemaetr = sqrt(three*j2)     ! 试算 von mises 等效应力

c-----------------------------------------------------------------
c     14. 计算 lode 角参数 fai（5 段分段函数）
c-----------------------------------------------------------------
        zj2 = 1.15d0/(one+1.3d0/(3.0d0*a1+2.3d0*a2*fc))

        if (rp.lt.zero) then
          fai = half
          dfaidp = zero
        else if (rp.lt.fc/three) then
          fai = half + 9.0d0*t/two/fc**2*rp
          dfaidp = 9.0d0*t/two/fc**2
        else if (rp.lt.two*1.15d0*fc/three) then
          fai = (zj2-half-3.0d0*t/two/fc)/(two*1.15d0*fc/three
     .        - fc/three)*(rp-fc/three) + half + 3.0d0*t/two/fc
          dfaidp = (zj2-half-3.0d0*t/two/fc)/(two*1.15d0*fc/three
     .           - fc/three)
        else if (rp.lt.three*fc) then
          fai = (0.753d0-zj2)/(three*fc-two*1.15d0*fc/three)
     .        * (rp-two*1.15d0*fc/three) + zj2
          dfaidp = (0.753d0-zj2)/(three*fc-two*1.15d0*fc/three)
        else if (rp.lt.8.45d0*fc) then
          fai = (one-0.753d0)/5.45d0/fc*(rp-three*fc) + 0.753d0
          dfaidp = (one-0.753d0)/5.45d0/fc
        else
          fai = one
          dfaidp = zero
        end if

        fai = max(half, min(one, fai))

c-----------------------------------------------------------------
c     15. 计算 lode 角参数 rat（用于强度面）
c         j2old、j3old、sita、cywh、rat
c-----------------------------------------------------------------
        j2old = half*(st(1)**2+st(2)**2+st(3)**2)
     .        + st(4)**2 + st(5)**2 + st(6)**2

        j3old = st(1)*(st(2)*st(3)-st(5)**2)
     .        - st(4)*(st(3)*st(4)-st(5)*st(6))
     .        + st(6)*(st(4)*st(5)-st(2)*st(6))
        j3old = -j3old
        j3old = j3old + sign(seps, j3old)
        kh = min(three*sqrt(three)/two*abs(j3old)
     .          /(j2old**1.5d0+seps), one)
        sita = acos(sign(kh, -j3old))/three
        ompsi2 = one - fai*fai
        tpsim1 = two*fai - one

        cywh = max(half, cos(sita))

        rat = 4.0d0*ompsi2*cywh**2 + 5.0d0*fai**2 - 4.0d0*fai
        sq = sqrt(max(rat, zot))
        rat = two*ompsi2*cywh + tpsim1*sq
        ratden = 4.0d0*ompsi2*cywh**2 + tpsim1*tpsim1
        rat = rat/ratden

c-----------------------------------------------------------------
c     16. 强度面 fcmin（压缩子午线）、fcmax（最大强度面）
c-----------------------------------------------------------------
        if (rp.le.zero) then
          fcmin = zero
          dfcndp = zero
        else
          fcmin = rp/(a1+a2*rp)
          dfcndp = a1/(a1+a2*rp)**2
        end if

        if (fcmin.lt.zero) then
          dfcndp = zero
          fcmin = zero
        end if

        if (rp.ge.fc/three) then
          fcmax = fc + (rp-fc/three)/(a1+a2*rp)
          dfcmdp = (a1+a2*fc/three)/(a1+a2*rp)**2
        else if (rp.ge.zero) then
          fcmax = 1.5d0*(rp+t)/fai
          dfcmdp = (1.5d0-dfaidp*fcmax)/fai
        else
          fcmax = three*t*(one-(rp-seps)/(rpcutoff-seps))
          dfcmdp = -three*t/rpcutoff
        end if

        if (fcmax.lt.zero) then
          dfcmdp = zero
          fcmax = zero
        end if

c       若 fcmin > fcmax，则强制相等
        if (fcmin.gt.fcmax) then
          fcmin = fcmax
          dfcndp = dfcmdp
        end if

c-----------------------------------------------------------------
c     17. 当前强度面 sigemay0（损伤耦合）
c-----------------------------------------------------------------
        sigemay0 = rat*dif*(eta*(fcmin-fcmax)+fcmax)

c-----------------------------------------------------------------
c     18. 径向返回（含 lode 角导数、损伤耦合、剪胀）
c-----------------------------------------------------------------
        dmunum = sigemaetr - sigemay0

        if (dmunum.gt.zero) then

c         强度面对 lode 角参数的偏导数
          drsdg = (-two*cywh*cywh*(two*ompsi2*cywh+tpsim1*sq)/ratden
     .           + (one+tpsim1/sq*cywh)*cywh)/ratden
          drsdh = (-two*tpsim1*(two*ompsi2*cywh+tpsim1*sq)/ratden
     .           + sq)/ratden
          drsdpsi = tpsim1/two/sq*(10.0d0*fai-4.0d0)/ratden
          drdpsi = -4.0d0*fai*drsdg + two*drsdh + drsdpsi

c         强度面对塑性乘子、压力的偏导数
          dydlam = eta_prime*(fcmin-fcmax)*rat*dif
          dydp = rat*(eta*dfcndp+(one-eta)*dfcmdp)
     .         + drdpsi*dfaidp*(eta*fcmin+(one-eta)*fcmax)

c         硬化/软化模量 hosig
          if (p.gt.zero) then
            hosig = one/(d1*(t/fc+rp/fc)**d2)
            hosig = hosig/dif
          else
            fdf = fdf1
            hosig = (one+fdf/three*dydp)
     .            / sqrt(one+two*(fdf*dydp/three)**2)
          end if

          r3g = one/three/g
          fdf = fdf1

c         计算塑性乘子增量 dlambda、剪胀 dpp
          term3 = fdf*bulkmod*dydp*r3g
          denom = one + term3*dydp
     .          + r3g*hosig*dydlam
     .          * sqrt(one+two*(fdf*dydp/three)**2)
          dmux = dmunum/(zot2 + abs(denom))
          dlambda = hosig*r3g*dmux
     .            * sqrt(one+two*(fdf*dydp/three)**2)
          dpp = term3*dmux
          sigemay0 = max(sigemay0+dydlam*dlambda+dydp*dpp, zero)

c         应力缩放因子（径向返回）
          if (denom.gt.zot2 .and. sigemaetr.gt.sigemay0) then
            sscale = (sigemay0+seps)/(sigemaetr+seps)
          else
            sscale = one
          end if

c         更新偏应力
          s(1) = sscale*st(1)
          s(2) = sscale*st(2)
          s(3) = sscale*st(3)
          s(4) = sscale*st(4)
          s(5) = sscale*st(5)
          s(6) = sscale*st(6)

c         压力修正（剪胀）
          p = p + dpp

c         损伤因子增量：拉/压分流
          if (p.le.zero) then
            uvar(i,12) = uvar(i,12) + dlambda     ! 拉伸损伤
          else
            uvar(i,5) = uvar(i,5) + dlambda       ! 剪切损伤
          end if

c         塑性体积应变累积
          uvar(i,3) = uvar(i,3) + dpp/bulkmod

c         等效塑性应变累积
          uvar(i,10) = uvar(i,10) + r3g*dmux
     .        * sqrt(one+two*(fdf*dydp/three)**2)

        else
c         弹性：直接采用试算偏应力
          s(1) = st(1)
          s(2) = st(2)
          s(3) = st(3)
          s(4) = st(4)
          s(5) = st(5)
          s(6) = st(6)
        end if

c-----------------------------------------------------------------
c     19. 体积损伤
c-----------------------------------------------------------------
        if (sigemaetr.lt.-0.1d0*p) then
          ff = abs(pnocut) - abs(pcutoff)
          fact = min(one, one-min(sigemay0,sigemaetr)/(-0.1d0*p))
          uvar(i,12) = uvar(i,12) + fact*d3*max(dmiu, zero)
          if (ff.gt.zero) then
            uvar(i,3) = uvar(i,3) + ff/kav
          end if
        end if

c-----------------------------------------------------------------
c     20. 更新应力（写回 userbuf）
c-----------------------------------------------------------------
        userbuf%signxx(i) = s(1) - p
        userbuf%signyy(i) = s(2) - p
        userbuf%signzz(i) = s(3) - p
        userbuf%signxy(i) = s(4)
        userbuf%signyz(i) = s(5)
        userbuf%signzx(i) = s(6)

c-----------------------------------------------------------------
c     21. 更新历史变量
c-----------------------------------------------------------------
        miul = 2750.0d0/row0 - one     ! 孔隙压实阈值
        uvar(i,6) = min(0.99999d0,
     .                 sqrt(max(zero,uvar(i,4))/miul))  ! 压实损伤
        uvar(i,7) = etac
        uvar(i,8) = etat
        uvar(i,9) = one - (one-uvar(i,6))*(one-uvar(i,7))
     .            * (one-uvar(i,8))                      ! 总损伤
        uvar(i,11) = eta

c-----------------------------------------------------------------
c     22. 输出接口
c-----------------------------------------------------------------
        pla(i) = uvar(i,9)   ! equivalent plastic strain
        sigy(i) = max(zero,sigemay0) ! integrated strength
        uvar(i,2) = uvar(i,9)             ! uvar(2) = uvar(9)

c-----------------------------------------------------------------
c     23. 声速与粘性
c-----------------------------------------------------------------
        soundsp(i) = sqrt((k
     .                    +4.0d0*g/three)/row0)
        viscmax(i) = zero

c-----------------------------------------------------------------
c     24. 粘性应力置零（kf 无粘性）
c-----------------------------------------------------------------
        userbuf%sigvxx(i) = zero
        userbuf%sigvyy(i) = zero
        userbuf%sigvzz(i) = zero
        userbuf%sigvxy(i) = zero
        userbuf%sigvyz(i) = zero
        userbuf%sigvzx(i) = zero

c-----------------------------------------------------------------
c     25. 塑性应变增量（供后续热/损伤耦合）
c         输出本步等效塑性应变增量
c-----------------------------------------------------------------
        userbuf%dpla(i) = max(zero,uvar(i,10)-epold)


      enddo

      return
      end