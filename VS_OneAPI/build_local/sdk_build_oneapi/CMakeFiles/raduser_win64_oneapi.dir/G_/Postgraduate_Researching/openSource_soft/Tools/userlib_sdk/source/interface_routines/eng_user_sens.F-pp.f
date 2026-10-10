# 1 "G:\Postgraduate_Researching\openSource_soft\Tools\userlib_sdk\source\interface_routines\eng_user_sens.F"
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




Chd|====================================================================
Chd|  ST_LECM
Chd|-- called by -----------
Chd|-- calls ---------------
Chd|====================================================================
      SUBROUTINE ENG_USER_SENS(TYP,ID)

!DEC$ ATTRIBUTES DLLEXPORT, DECORATE, ALIAS : "ENG_USER_SENS" :: ENG_USER_SENS
!DEC$ ATTRIBUTES REFERENCE :: ID,TYP

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

# 39 "G:\Postgraduate_Researching\openSource_soft\Tools\userlib_sdk\source\interface_routines\eng_user_sens.F" 2 
C-----------------------------------------------
C   I n p u t     A r g u m e n t s
C-----------------------------------------------
      INTEGER ID,TYP
C-----------------------------------------------
C   L o c a l   V a r i a b l e s
C-----------------------------------------------
C-----------------------------------------------

      IF (TYP==29)THEN
          CALL USER_SENS1(ID)
      ELSEIF(TYP==30)THEN
          CALL USER_SENS2(ID)
      ELSEIF(TYP==31)THEN
          CALL USER_SENS3(ID)
      ENDIF



      END
