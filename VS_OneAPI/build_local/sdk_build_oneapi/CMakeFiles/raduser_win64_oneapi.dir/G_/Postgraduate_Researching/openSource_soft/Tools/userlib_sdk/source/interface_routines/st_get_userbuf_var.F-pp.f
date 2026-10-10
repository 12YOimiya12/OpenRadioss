# 1 "G:\Postgraduate_Researching\openSource_soft\Tools\userlib_sdk\source\interface_routines\st_get_userbuf_var.F"
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
Chd|  ST_GET_USERBUF_VAR                        src/user1/lecm99.F
Chd|-- called by -----------
Chd|        LECMUSER                      src/mater1/lecmuser.F
Chd|-- calls ---------------
Chd|====================================================================
      SUBROUTINE ST_GET_USERBUF_VAR( ID,NAME)

!DEC$ ATTRIBUTES DLLEXPORT, DECORATE, ALIAS : "ST_GET_USERBUF_VAR" :: ST_GET_USERBUF_VAR
!DEC$ ATTRIBUTES REFERENCE :: ID,NAME


      USE ST_ULAW
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

# 42 "G:\Postgraduate_Researching\openSource_soft\Tools\userlib_sdk\source\interface_routines\st_get_userbuf_var.F" 2 
C-----------------------------------------------
C   D u m m y   A r g u m e n t s
C-----------------------------------------------
      INTEGER ID
      CHARACTER*500 NAME
C-----------------------------------------------
      ID = USERBUF%ID
      NAME = USERBUF%NAME

      END
