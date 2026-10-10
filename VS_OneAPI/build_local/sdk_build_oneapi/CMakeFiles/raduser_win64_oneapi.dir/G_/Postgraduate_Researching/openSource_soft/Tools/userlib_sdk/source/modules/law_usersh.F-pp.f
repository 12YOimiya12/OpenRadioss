# 1 "G:\Postgraduate_Researching\openSource_soft\Tools\userlib_sdk\source\modules\law_usersh.F"
Copyright>
Copyright> Copyright (C) 2026 SISW Siemens Industry Software Inc.
Copyright>
Copyright> Permission is hereby granted, free of charge, to any person obtaining
Copyright> a copy of this software and associated documentation files (the "Software"),
Copyright> to deal in the Software without restriction, including without limitation
Copyright> the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
Copyright> sell copies of the Software, and to permit persons to whom the Software is
Copyright> furnished to do so, subject to the following conditions:
Copyright>
Copyright> The above copyright notice and this permission notice shall be included in all
Copyright> copies or substantial portions of the Software.
Copyright>
Copyright> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
Copyright> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
Copyright> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
Copyright> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
Copyright> WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
Copyright> IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
Copyright>




Csm51i6 Nouvelle routine
Chd|====================================================================
Chd|  LAW_USERSH                    src/usermodules/law_usersh.F
Chd|-- called by -----------
Chd|        LUSER44C                      pub/usersh/luser44c.F
Chd|        LUSER33C                      pub/usersh/luser33c.F
Chd|        LUSER25C                      pub/usersh/luser25c.F
Chd|        LUSER35C                      pub/usersh/luser35c.F
Chd|        LUSER72C                      pub/usersh/luser72c.F
Chd|        LUSER94C                      pub/usersh/luser94c.F
Chd|        LUSER11C                      pub/usersh/luser11c.F
Chd|        LUSER88C                      pub/usersh/luser88c.F
Chd|        LUSER62C                      pub/usersh/luser62c.F
Chd|        LUSER42C                      pub/usersh/luser42c.F
Chd|        LUSER20C                      pub/usersh/luser20c.F
Chd|        LUSER17C                      pub/usersh/luser17c.F
Chd|        LUSER52C                      pub/usersh/luser52c.F
Chd|        LUSER99C                      pub/usersh/luser99c.F
Chd|        LUSER40C                      pub/usersh/luser40c.F
Chd|        LUSER95C                      pub/usersh/luser95c.F
Chd|        LUSER14C                      pub/usersh/luser14c.F
Chd|        LUSER92C                      pub/usersh/luser92c.F
Chd|        LUSER91C                      pub/usersh/luser91c.F
Chd|        LUSER30C                      pub/usersh/luser30c.F
Chd|        LUSER57C                      pub/usersh/luser57c.F
Chd|        LUSER27C                      pub/usersh/luser27c.F
Chd|        LUSER31C                      pub/usersh/luser31c.F
Chd|        LUSER03C                      pub/usersh/luser03c.F
Chd|        LUSER64C                      pub/usersh/luser64c.F
Chd|        LUSER49C                      pub/usersh/luser49c.F
Chd|        LUSER10C                      pub/usersh/luser10c.F
Chd|        LUSER74C                      pub/usersh/luser74c.F
Chd|        LUSER98C                      pub/usersh/luser98c.F
Chd|        LUSER50C                      pub/usersh/luser50c.F
Chd|        LUSER12C                      pub/usersh/luser12c.F
Chd|        LUSER38C                      pub/usersh/luser38c.F
Chd|        LUSER47C                      pub/usersh/luser47c.F
Chd|        LUSER24C                      pub/usersh/luser24c.F
Chd|        LUSER51C                      pub/usersh/luser51c.F
Chd|        LUSER79C                      pub/usersh/luser79c.F
Chd|        LUSER46C                      pub/usersh/luser46c.F
Chd|        LUSER19C                      pub/usersh/luser19c.F
Chd|        LUSER87C                      pub/usersh/luser87c.F
Chd|        LUSER45C                      pub/usersh/luser45c.F
Chd|        LUSER55C                      pub/usersh/luser55c.F
Chd|        LUSER71C                      pub/usersh/luser71c.F
Chd|        LUSER69C                      pub/usersh/luser69c.F
Chd|        LUSER05C                      pub/usersh/luser05c.F
Chd|        LUSER65C                      pub/usersh/luser65c.F
Chd|        LUSER76C                      pub/usersh/luser76c.F
Chd|        LUSER16C                      pub/usersh/luser16c.F
Chd|        LUSER09C                      pub/usersh/luser09c.F
Chd|        LUSER23C                      pub/usersh/luser23c.F
Chd|        LUSER22C                      pub/usersh/luser22c.F
Chd|        LUSER54C                      pub/usersh/luser54c.F
Chd|        LUSER04C                      pub/usersh/luser04c.F
Chd|        LUSER15C                      pub/usersh/luser15c.F
Chd|        SIGEPS99C                     src/user/sigeps99c.F
Chd|        LUSER61C                      pub/usersh/luser61c.F
Chd|        LUSER21C                      pub/usersh/luser21c.F
Chd|        LUSER39C                      pub/usersh/luser39c.F
Chd|        LUSER48C                      pub/usersh/luser48c.F
Chd|        LUSER97C                      pub/usersh/luser97c.F
Chd|        LUSER93C                      pub/usersh/luser93c.F
Chd|        LUSER67C                      pub/usersh/luser67c.F
Chd|        LUSER56C                      pub/usersh/luser56c.F
Chd|        MULAWC                        src/coque/mulawc.F
Chd|        LUSER83C                      pub/usersh/luser83c.F
Chd|        LUSER80C                      pub/usersh/luser80c.F
Chd|        LUSER01C                      pub/usersh/luser01c.F
Chd|        LUSER70C                      pub/usersh/luser70c.F
Chd|        LUSER58C                      pub/usersh/luser58c.F
Chd|        LUSER28C                      pub/usersh/luser28c.F
Chd|        LUSER29C                      pub/usersh/luser29c.F
Chd|        LUSER86C                      pub/usersh/luser86c.F
Chd|        LUSER07C                      pub/usersh/luser07c.F
Chd|        LUSER63C                      pub/usersh/luser63c.F
Chd|        LUSER85C                      pub/usersh/luser85c.F
Chd|        LUSER78C                      pub/usersh/luser78c.F
Chd|        LUSER84C                      pub/usersh/luser84c.F
Chd|        LUSER82C                      pub/usersh/luser82c.F
Chd|        LUSER26C                      pub/usersh/luser26c.F
Chd|        LUSER81C                      pub/usersh/luser81c.F
Chd|        LUSER18C                      pub/usersh/luser18c.F
Chd|        LUSER89C                      pub/usersh/luser89c.F
Chd|        LUSER06C                      pub/usersh/luser06c.F
Chd|        LUSER08C                      pub/usersh/luser08c.F
Chd|        LUSER60C                      pub/usersh/luser60c.F
Chd|        LUSER59C                      pub/usersh/luser59c.F
Chd|        LUSER36C                      pub/usersh/luser36c.F
Chd|        LUSER75C                      pub/usersh/luser75c.F
Chd|        LUSER53C                      pub/usersh/luser53c.F
Chd|        LUSER66C                      pub/usersh/luser66c.F
Chd|        LUSER77C                      pub/usersh/luser77c.F
Chd|        LUSER96C                      pub/usersh/luser96c.F
Chd|        LUSER43C                      pub/usersh/luser43c.F
Chd|        LUSER32C                      pub/usersh/luser32c.F
Chd|        LUSER37C                      pub/usersh/luser37c.F
Chd|        LUSER41C                      pub/usersh/luser41c.F
Chd|        LUSER68C                      pub/usersh/luser68c.F
Chd|        LUSER02C                      pub/usersh/luser02c.F
Chd|        LUSER90C                      pub/usersh/luser90c.F
Chd|        LUSER13C                      pub/usersh/luser13c.F
Chd|        LUSER34C                      pub/usersh/luser34c.F
Chd|        LUSER73C                      pub/usersh/luser73c.F
Chd|-- calls ---------------
Chd|====================================================================
      MODULE LAW_USERSH
C-----------------------------------------------
C   D e r i v e d   T y p e   D e f i n i t i o n s
C-----------------------------------------------
C-----------------------------------------------
C   I m p l i c i t   T y p e s
C-----------------------------------------------
# 1 "G:\Postgraduate_Researching\openSource_soft\Tools\userlib_sdk\source\includes\implicit_f.inc" 1 
Copyright>
Copyright> Copyright (C) 2026 SISW Siemens Industry Software Inc.
Copyright>
Copyright> Permission is hereby granted, free of charge, to any person obtaining
Copyright> a copy of this software and associated documentation files (the "Software"),
Copyright> to deal in the Software without restriction, including without limitation
Copyright> the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
Copyright> sell copies of the Software, and to permit persons to whom the Software is
Copyright> furnished to do so, subject to the following conditions:
Copyright>
Copyright> The above copyright notice and this permission notice shall be included in all
Copyright> copies or substantial portions of the Software.
Copyright>
Copyright> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
Copyright> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
Copyright> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
Copyright> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
Copyright> WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
Copyright> IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
Copyright>
# 23






      IMPLICIT NONE 

# 140 "G:\Postgraduate_Researching\openSource_soft\Tools\userlib_sdk\source\modules\law_usersh.F" 2 
C-----------------------------------------------
C   G l o b a l   P a r a m e t e r s
C-----------------------------------------------
# 1 "G:\Postgraduate_Researching\openSource_soft\Tools\userlib_sdk\source\includes\mvsiz_p.inc" 1 
Copyright>
Copyright> Copyright (C) 2026 SISW Siemens Industry Software Inc.
Copyright>
Copyright> Permission is hereby granted, free of charge, to any person obtaining
Copyright> a copy of this software and associated documentation files (the "Software"),
Copyright> to deal in the Software without restriction, including without limitation
Copyright> the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
Copyright> sell copies of the Software, and to permit persons to whom the Software is
Copyright> furnished to do so, subject to the following conditions:
Copyright>
Copyright> The above copyright notice and this permission notice shall be included in all
Copyright> copies or substantial portions of the Software.
Copyright>
Copyright> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
Copyright> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
Copyright> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
Copyright> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
Copyright> WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
Copyright> IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
Copyright>
      INTEGER MVSIZ
      PARAMETER (MVSIZ = 129)
# 144 "G:\Postgraduate_Researching\openSource_soft\Tools\userlib_sdk\source\modules\law_usersh.F" 2 
C---------+---------+---+---+--------------------------------------------
C VAR     | SIZE    |TYP| RW| DEFINITION
C---------+---------+---+---+--------------------------------------------
C IPT     |  1      | I | R | LAYER OR INTEGRATION POINT NUMBER
C IFLAG   |  *      | I | R | GEOMETRICAL FLAGS
C---------+---------+---+---+--------------------------------------------
C EPSPXX  | NEL     | F | R | STRAIN RATE XX
C EPSPYY  | NEL     | F | R | STRAIN RATE YY
C ...     |         |   |   |
C DEPSXX  | NEL     | F | R | STRAIN INCREMENT XX
C DEPSYY  | NEL     | F | R | STRAIN INCREMENT YY
C ...     |         |   |   |
C EPSXX   | NEL     | F | R | STRAIN XX
C EPSYY   | NEL     | F | R | STRAIN YY
C ...     |         |   |   |
C SIGOXX  | NEL     | F | R | OLD ELASTO PLASTIC STRESS XX
C SIGOYY  | NEL     | F | R | OLD ELASTO PLASTIC STRESS YY
C ...     |         |   |   |
C---------+---------+---+---+--------------------------------------------
C SIGNXX  | NEL     | F | W | NEW ELASTO PLASTIC STRESS XX
C SIGNYY  | NEL     | F | W | NEW ELASTO PLASTIC STRESS YY
C ...     |         |   |   |
C SIGVXX  | NEL     | F | W | VISCOUS STRESS XX
C SIGVYY  | NEL     | F | W | VISCOUS STRESS YY
C ...     |         |   |   |
C---------+---------+---+---+--------------------------------------------
C DPLA    | NEL     | F |R/W| INCREMENTAL PLASTIC STRAIN
C---------+---------+---+---+--------------------------------------------
C
      TYPE ULAWCINTBUF
C integer
        INTEGER  NCYCLE
        INTEGER  ID
        INTEGER  ILAYER
        INTEGER  NPTA
        INTEGER  IPG
        INTEGER  IFLAG
C floating
!         DOUBLE PRECISION, DIMENSION(2*MVSIZ*NPT) :: DIR_A, DIR_B
!         DOUBLE PRECISION DIR_A(2,MVSIZ*NPTA)
!         DOUBLE PRECISION DIR_B(2,MVSIZ*NPTA)
        DOUBLE PRECISION R11(MVSIZ)
        DOUBLE PRECISION R12(MVSIZ)
        DOUBLE PRECISION R13(MVSIZ)
C
        DOUBLE PRECISION R21(MVSIZ)
        DOUBLE PRECISION R22(MVSIZ)
        DOUBLE PRECISION R23(MVSIZ)
C
        DOUBLE PRECISION R31(MVSIZ)
        DOUBLE PRECISION R32(MVSIZ)
        DOUBLE PRECISION R33(MVSIZ)
C
!         DOUBLE PRECISION DIR_A(MVSIZ)
!         DOUBLE PRECISION DIR_B(MVSIZ)
C
        DOUBLE PRECISION THKLYL(MVSIZ)
        DOUBLE PRECISION THKN(MVSIZ)
        DOUBLE PRECISION EPSPXX(MVSIZ)
        DOUBLE PRECISION EPSPYY(MVSIZ)
        DOUBLE PRECISION EPSPXY(MVSIZ)
        DOUBLE PRECISION EPSPYZ(MVSIZ)
        DOUBLE PRECISION EPSPZX(MVSIZ)
c
        DOUBLE PRECISION EPSXX(MVSIZ)
        DOUBLE PRECISION EPSYY(MVSIZ)
        DOUBLE PRECISION EPSXY(MVSIZ)
        DOUBLE PRECISION EPSYZ(MVSIZ)
        DOUBLE PRECISION EPSZX(MVSIZ)
C--------when Ismstr=10 we input [F]
        DOUBLE PRECISION FPSXX(MVSIZ)
        DOUBLE PRECISION FPSYY(MVSIZ)
        DOUBLE PRECISION FPSZZ(MVSIZ)
        DOUBLE PRECISION FPSXY(MVSIZ)
        DOUBLE PRECISION FPSYX(MVSIZ)
C
        DOUBLE PRECISION DEPSXX(MVSIZ)
        DOUBLE PRECISION DEPSYY(MVSIZ)
        DOUBLE PRECISION DEPSXY(MVSIZ)
        DOUBLE PRECISION DEPSYZ(MVSIZ)
        DOUBLE PRECISION DEPSZX(MVSIZ)
C
        DOUBLE PRECISION SIGOXX(MVSIZ)
        DOUBLE PRECISION SIGOYY(MVSIZ)
        DOUBLE PRECISION SIGOXY(MVSIZ)
        DOUBLE PRECISION SIGOYZ(MVSIZ)
        DOUBLE PRECISION SIGOZX(MVSIZ)
        
        DOUBLE PRECISION TEMP(MVSIZ)      ! temperature
C-----------------------------------------------
C   O U T P U T   A r g u m e n t s
C-----------------------------------------------
        DOUBLE PRECISION SIGNXX(MVSIZ)
        DOUBLE PRECISION SIGNYY(MVSIZ)
        DOUBLE PRECISION SIGNXY(MVSIZ)
        DOUBLE PRECISION SIGNYZ(MVSIZ)
        DOUBLE PRECISION SIGNZX(MVSIZ)
C
        DOUBLE PRECISION SIGVXX(MVSIZ)
        DOUBLE PRECISION SIGVYY(MVSIZ)
        DOUBLE PRECISION SIGVXY(MVSIZ)
        DOUBLE PRECISION SIGVYZ(MVSIZ)
        DOUBLE PRECISION SIGVZX(MVSIZ)
    
        DOUBLE PRECISION ETSE(MVSIZ)
        DOUBLE PRECISION DPLA(MVSIZ)
      
       END TYPE ULAWCINTBUF
C-----------------------------------------------
C   I N P U T   O U T P U T   A r g u m e n t s
C-----------------------------------------------
      END MODULE LAW_USERSH
      
