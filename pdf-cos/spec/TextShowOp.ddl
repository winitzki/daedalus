-- TextShowOp: text showing operators
import Stdlib

import PdfValue
import GenPdfValue
import TextEffect

-- TODO: non-immediate dep
import Unicode

-- TJOper: operands in a use of TJ
def TJOper = Choose1 {
  shownString = String;
  hexBytes = HexString;
  adjustNum = Number;
}

def TextShowOper = Choose1 { -- operations are mutually exclusive:
  showString = {
    $$ = Token (String <| HexString)  ;
    KW "Tj" 
  };
  showManyStrings = {
    $$ = GenArray TJOper;
    KW "TJ"
  };
}

-- Text-showing operators (Table 107)
def TextShowOp (f : ?sizedFont) = {
  showFont = f;
  oper = TextShowOper;
}

def ShowStringOp (szFont : ?sizedFont) (s : [uint 8]) : TextShowOp = {
  showFont = szFont;
  oper = {| showString = s |};
}

-- this is the size of visible space, to me
def visible = 200 : int

-- Text-showing operators: Table 107
def ShowTextShow (op: TextShowOp) (q : textState) : [ UTF8 ] =
  case (op.oper: TextShowOper) of {
    showString arg -> ExtractString q op.showFont arg
  ; showManyStrings args ->
    for (acc = []; a in args) {
      append acc (case (a : TJOper) of {
          shownString s -> ExtractString q op.showFont s
        ; hexBytes bs -> ExtractString q op.showFont bs
        ; adjustNum n -> optionToArray (condJust
            ((0 - n.num) > visible)
            (mkUTF81 (bytes1 ' ')) )
        })
    }
  }
