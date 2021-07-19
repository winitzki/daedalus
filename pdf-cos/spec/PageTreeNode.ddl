-- PageTreeNode: parse a page tree node. Ensures that the page tree
-- actually forms a tree.
import Stdlib
import Pair
import Array
import Map

import GenPdfValue
import PdfValue
import ResourceDict
import Page

def PartialPageTreeNode (resrcs : maybe Pair) = {
  type0 = false;
  parent0 = false;
  kids0 = nothing;
  count0 = nothing;
  nodeResources0 = resrcs;
  others0 = empty;
}

def AddType pageTree : PartialPageTreeNode = {
  type0 = Holds (NameToken "Pages");

  parent0 = pageTree.parent0;
  kids0 = pageTree.kids0;
  count0 = pageTree.count0;
  nodeResources0 = pageTree.nodeResources0;
  others0 = pageTree.others0;
}

def AddParent (par: Ref) pageTree : PartialPageTreeNode = {
  type0 = pageTree.type0;

  parent0 = Holds (Guard (Token Ref == par));

  kids0 = pageTree.kids0;
  count0 = pageTree.count0;
  nodeResources0 = pageTree.nodeResources0;
  others0 = pageTree.others0;
}

def AddKids pageTree : PartialPageTreeNode = {
  type0 = pageTree.type0;
  parent0 = pageTree.parent0;

  kids0 = just (GenArray Ref);

  count0 = pageTree.count0;
  nodeResources0 = pageTree.nodeResources0;
  others0 = pageTree.others0;
}

def AddCount pageTree : PartialPageTreeNode = {
  type0 = pageTree.type0;
  parent0 = pageTree.parent0;
  kids0 = pageTree.kids0;

  count0 = just (DirectOrRef Natural);

  nodeResources0 = pageTree.nodeResources0;
  others0 = pageTree.others0;
}

def NodeAddResources pageTree : PartialPageTreeNode = {
  type0 = pageTree.type0;
  parent0 = pageTree.parent0;
  kids0 = pageTree.kids0;
  count0 = pageTree.count0;

  nodeResources0 = LocalDefn (DirectOrRef ResourceDictP);

  others0 = pageTree.others0;
}

def NodeAddOther k pageTree : PartialPageTreeNode = {
  type0 = pageTree.type0;
  parent0 = pageTree.parent0;
  kids0 = pageTree.kids0;
  count0 = pageTree.count0;
  nodeResources0 = pageTree.nodeResources0;

  others0 = Extend k (Token Value) pageTree.others0;
}

def RefHistory (os: [ Ref ]) (p : Ref) = {
  others = os;
  parent = p;
}

def SeenParent (par : Ref) (h: RefHistory) = {
  histOthers = cosn h.parent h.others;
  histParent = par;
}

def PageTreeNodeRec (seen : maybe RefHistory) (cur : Ref) pageTree =
  Default pageTree 
  { @k = Token Name;
    @pageTree0 = if k == "Type" then {
        pageTree.type0 is false;
        AddType pageTree
      }
      else if k == "Parent" then {
        pageTree.parent0 is false;
        seen is just;
        AddParent seen.histParent pageTree
      }
      else if k == "Kids" then  {
        pageTree.kids0 is nothing;
        AddKids pageTree;
      }
      else if k == "Count" then {
        pageTree.kids0 is nothing;
        AddCount pageTree
      }
      else if k == "Resources" then {
        CheckNoLocalDefn pageTree.nodeResources0;
        NodeAddResources pageTree
      }
      else NodeAddOther k pageTree;
    PageTreeNodeRec seen cur pageTree0
  }

def CheckKidsCount kids size = {
  @kidsCount = for (kidsCountAcc = 0; kid in kids)
    (kidsCountAcc + (pageNodeKidCount kid));
  Guard (size == kidsCount)
}

def ParseKidRefs (resrcs: maybe Pair) seen cur kidRefs = {
  @res0 = Pair [ ] (cons cur seen);
  for (accRes = res0; kidRef in kidRefs) { 
    Guard (!(member kidRef accRes.snd)); -- the check for cycle detection
    @kidRes = ParseAtRef kidRef (PageNodeKid resrcs accRes.snd cur kidRef);
    Pair (snoc kidRes.fst accRes.fst) (append kidRes.snd accRes.snd)
  }
}

-- PageTreeNode: coerce an partial page-tree node into a page
-- tree node
def PageTreeNode seen (cur : Ref) pt0 = {
  Guard pt0.type0;
  Guard pt0.parent0;
  @kidRefs = pt0.kids0 is just;

  @kidsAndSeen = ParseKidRefs pt0.nodeResources0 seen cur kidRefs;
  Pair {
      kids = kidsAndSeen.fst;      
      count = pt0.count0 is just; 
      CheckKidsCount kids count;
      others = pt0.others0;
    }
    kidsAndSeen.snd
}

def PageNodeKid (resrcs : maybe Pair) seen (cur : Ref) (r : Ref) = Choose1 {
  Pair {| pageKid = Page (Bestow resrcs) cur |} [ ];
  { @x = PageTreeNodeP (Bestow resrcs) seen cur r;
    Pair {| treeKid = x.fst |} x.snd
  };
}

-- pageNodeKidCount k: number of pages under kid k
def pageNodeKidCount (k : PageNodeKid) = case k of {
  pageKid _ -> 1;
  treeKid k -> k.count;
}

def PageTreeNodeP resrcs seen (cur: Ref) = Between "<<" ">>" {
  @initPageTree = PartialPageTreeNode (Inherit resrcs);
  @ptRec = PageTreeNodeRec seen cur initPageTree;
  PageTreeNode (SeenParent par seen) cur ptRec
}
