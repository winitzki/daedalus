--------------------------------------------------------------------------------
-- Parsing Basic Types

def joinWords a b = if ?bigEndian then a # b else b # a

def UInt16        = joinWords UInt8 UInt8
def UInt32        = joinWords UInt16 UInt16
def UInt64        = joinWords UInt32 UInt32

def SInt16        = UInt16 as! sint 16
def SInt32        = UInt32 as! sint 32
def SInt64        = UInt64 as! sint 64

def HalfFloat     = wordToHalfFloat UInt16
def Float         = wordToFloat UInt32
def Double        = wordToDouble UInt64

def BEUInt16      = block let ?bigEndian = true; UInt16
def BEUInt32      = block let ?bigEndian = true; UInt32
def BEUInt64      = block let ?bigEndian = true; UInt64

def BESInt16      = block let ?bigEndian = true; SInt16
def BESInt32      = block let ?bigEndian = true; SInt32
def BESInt64      = block let ?bigEndian = true; SInt64

def BEHalfFloat   = block let ?bigEndian = true; HalfFloat
def BEFloat       = block let ?bigEndian = true; Float
def BEDouble      = block let ?bigEndian = true; Double

def LEUInt16      = block let ?bigEndian = false; UInt16
def LEUInt32      = block let ?bigEndian = false; UInt32
def LEUInt64      = block let ?bigEndian = false; UInt64

def LESInt16      = block let ?bigEndian = false; SInt16
def LESInt32      = block let ?bigEndian = false; SInt32
def LESInt64      = block let ?bigEndian = false; SInt64

def LEHalfFloat   = block let ?bigEndian = false; HalfFloat
def LEFloat       = block let ?bigEndian = false; Float
def LEDouble      = block let ?bigEndian = false; Double

-- See: https://fgiesen.wordpress.com/2012/03/28/half-to-float-done-quic/
-- for an explanation of what's going on here.
def wordToHalfFloat (w : uint 16) =
  block
    let sign = w >> 15 as! uint 1
    let expo = w >> 10 as! uint 5
    let mant = w       as! uint 10
    if expo == 0
      then
        block
          let magic = 126 << 23 : uint 32
          let num   = wordToFloat (magic + (0 # mant)) - wordToFloat magic
          if sign == 1 then -num else num
      else
        block
         let newExp =
                if expo == 0x1F then 0xFF else 127 - 15 + (0 # expo) : uint 8
         wordToFloat (sign # newExp # mant # 0)

--------------------------------------------------------------------------------

-- Succeed if the condition holds or fail otherwise.
def Guard b       = b is true

-- Succeed if `P` consumes all input.
def Only P        = block $$ = P; END


--------------------------------------------------------------------------------

def min x y = if x < y then x else y
def max x y = if x < y then y else x



--------------------------------------------------------------------------------
-- Stream Manipulation

-- Set the stream to the `n`-th byte of `s`.
def SetStreamAt n s = SetStream (Drop n s)

-- Advance the current stream by `n` bytes.
def Skip n          = SetStreamAt n GetStream

-- Parse the following `n` bytes using `P`.
-- Note that `P` does not have to consume all of the bytes,
-- but we still advance by `n`.  Use `Only` if you want to ensure
-- that `P` consumes the whole input.
def Chunk n P =
  block
    let s = GetStream
    SetStream (Take n s)
    $$ = P
    SetStreamAt n s

-- Get a chunk of unprocessed bytes.
def Bytes n = Chunk n GetStream

-- Parse using `P` but reset the stream to the current position on success.
def LookAhead P =
  block
    let s = GetStream
    $$ = P
    SetStream s






