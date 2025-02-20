import Pair
import Sum

def Unit = ^{}

def IgnoreResult P : {} = {P; ^{}}

def Void = Choose1 { }

def FoldMany P acc = Choose1 {
  { @acc0 = P acc;
    FoldMany P acc0
  };
  ^ acc
}

def Const P x = P

def boolXor b0 b1 = if b0 then !b1 else b1

def inc n = n + 1
def dec n = n - 1
def max m n = if m > n then m else n
def min m n = if m < n then m else n
def bitIsSet8 (n : uint 8) bs = (n .&. (1 << bs)) != 0
def bitIsSet32 (n : uint 32) bs = (n .&. (1 << bs)) != 0
def setBit bs (n : uint 32) = n .|. (1 << bs)

def truncate8to4 (n : uint 8) : uint 4 = (n .&. 0x0F) as! uint 4

def numBase base ds       = for (val = 0; d in ds) (val * base + d)
def bytesNum (bs : [ uint 8 ]) : uint 64 =
  for (val = 0 : uint 64; b in bs) 8 * val + (b as uint 64)

def octalTriple a b c = numBase 8 [ a, b, c ]

def Only P                = { $$ = P; END }
def When P x              = { P; ^ x }
def GuardMsg p s          = case p of
                              true  -> Unit
                              false -> Fail (concat ["Guard failed: ", s])
def Guard p               = p is true
def Holds P = When P true

def append x y = concat [ x, y ]

def cons x xs = append [ x ] xs

def snoc x xs = append xs [ x ]

def condJust p x = if p then just x else nothing

def OptionalIf P N = case Optional P of {
  just x -> just x
; nothing -> When N nothing
}

def optionToArray x = case x of
  just y -> [ y ]
  nothing -> [ ]

def optionsToArray (xs : [ maybe ?a ]) : [ ?a ] = concat
  (map (x in xs) optionToArray x)

-- bounded sequences of bytes:
def OrEatByte P = OptionalIf P UInt8

def bytes1 (b : uint 8) = {
  only = b
}

def Bytes1P = bytes1 UInt8

def bytes2 (high : uint 8) (others : bytes1) = {
  second = high
; rest1 = others
}

def bytes2All (high : uint 8) (low : uint 8) = bytes2 high (bytes1 low)

def Bytes2P = bytes2 UInt8 Bytes1P

def bytes3 (pthird : uint 8) (others : bytes2) = {
  third = pthird;
  rest2 = others;
}

def Bytes3P = bytes3 UInt8 Bytes2P

def bytes4 (pfourth : uint 8) (others : bytes3) = {
  fourth = pfourth;
  rest3 = others;
}

def bytes4All (b0 : uint 8) (b1 : uint 8) (b2 : uint 8) (b3 : uint 8) = 
  bytes4 b0 (bytes3 b1 (bytes2 b2 (bytes1 b3)))

def Bytes4P = bytes4 UInt8 Bytes3P

-- functions for serializing bounded structures into arrays
def bndBytes1 bs1 = [ bs1.only ]

def bndBytes2 bs2 = cons bs2.second (bndBytes1 bs2.rest1)

def bndBytes3 bs3 = cons bs3.third (bndBytes2 bs3.rest2)

def bndBytes4 bs4 = cons bs4.fourth (bndBytes3 bs4.rest3)

def Default x P = P <| ^ x

def GenMany P acc0 =
  { @acc1 = P acc0;
    GenMany P acc1
  } <|
  ^acc0

def ManyWithStateRec P q (res : [ ?a ]) : pair = Default (pair q res) {
  @eff = P q;
  ManyWithStateRec P eff.fst (append res (optionToArray eff.snd))
}

def ManyWithState P q0 = ManyWithStateRec P q0 [ ]

def WithStream s P = {
  @cur = GetStream;
  SetStream s;
  $$ = P;
  SetStream cur;
}

def sepLists2 ls : pair = {
  fst = optionsToArray (map (x in ls) getLeft x);
  snd = optionsToArray (map (x in ls) getRight x);
}

def Lists2 P0 P1 = {
  @xs = Many (Sum P0 P1);
  sepLists2 xs
}

def lenLists2 ls =
  (length ls.fst) +
  (length ls.snd)


