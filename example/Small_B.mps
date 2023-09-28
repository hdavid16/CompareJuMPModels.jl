NAME mip1
OBJSENSE MAX
ROWS
 N  OBJ
 G  z0      
 L  z1      
COLUMNS
    MARKER    'MARKER'                 'INTORG'
    z         OBJ       2
    z         z1        3
    y         OBJ       1
    y         z0        1
    y         z1        2
    x         OBJ       1
    x         z0        1
    x         z1        1
    MARKER    'MARKER'                 'INTEND'
RHS
    RHS1      z0        1
    RHS1      z1        4
BOUNDS
 BV BND1      z       
 BV BND1      y       
 BV BND1      x       
ENDATA
