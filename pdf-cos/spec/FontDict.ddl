import Stdlib
import Pair

import CMap
import CIDFont
import Encoding
import PdfValue
import TrueTypeFont
import Type0Font
import Type1Font
import Type3Font

def FontDict = Choose1 { 
  -- fonts are mutually exclusive, due to at least the Subtype field
  --  these all dictionaries, all contain << /Type /Font >>
  type0 = Type0FontP;
  type1 = Type1FontP;
  mmfont = MMFontP;
  type3 = Type3FontP;
  trueType = TrueTypeFont; 
}

def MkType0Font (f0 : Type0Font) : FontDict = {| type0 = f0 |}

def MkType1Font (f1 : Type1Font) : FontDict = {| type1 = f1 |}

-- def FontDictP = When Value (MkType1Font Type1FontStub)
def FontDictP = FontDict
