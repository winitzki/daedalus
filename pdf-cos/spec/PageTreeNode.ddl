-- PageTreeNode: parse a page tree node. Ensures that the page tree
-- actually forms a tree.
import Stdlib
import Array
import Map

import GenPdfValue
import PdfValue
import ResourceDict
import Page

def PageTreeNode0 (resrcs : maybe Pair) = {
  type0 = false;
  parent0 = false;
  kids0 = nothing;
  count0 = nothing;
  nodeResources0 = resrcs;
  others0 = empty;
}

def PageNodeKid (resrcs : maybe Pair) (cur : Ref) (r : Ref) = Choose1 {
  pageKid = Page (Bestow resrcs) cur;
  treeKid = PageTreeNodeP (Bestow resrcs) cur r;
}

def pageNodeKidCount (k : PageNodeKid) = case k of {
  pageKid -> 1;
  treeKid k -> k.count;
}

def AddType pageTree : PageTreeNode0 = {
  type0 = Holds (NameToken "Pages");

  parent0 = pageTree.parent0;
  kids0 = pageTree.kids0;
  count0 = pageTree.count0;
  nodeResources0 = pageTree.nodeResources0;
  others0 = pageTree.others0;
}

def AddParent (par: Ref) pageTree : PageTreeNode0 = {
  type0 = pageTree.type0;

  parent0 = Holds {
    @r = Token Ref;
    Guard (r == par);
  };

  kids0 = pageTree.kids0;
  count0 = pageTree.count0;
  nodeResources0 = pageTree.nodeResources0;
  others0 = pageTree.others0;
}

def AddKids pageTree : PageTreeNode0 = {
  type0 = pageTree.type0;
  parent0 = pageTree.parent0;

  kids0 = just (GenArray Ref);

  count0 = pageTree.count0;
  nodeResources0 = pageTree.nodeResources0;
  others0 = pageTree.others0;
}

def AddCount pageTree : PageTreeNode0 = {
  type0 = pageTree.type0;
  parent0 = pageTree.parent0;
  kids0 = pageTree.kids0;

  count0 = just (DirectOrRef Natural);

  nodeResources0 = pageTree.nodeResources0;
  others0 = pageTree.others0;
}

def NodeAddResources pageTree : PageTreeNode0 = {
  type0 = pageTree.type0;
  parent0 = pageTree.parent0;
  kids0 = pageTree.kids0;
  count0 = pageTree.count0;

  nodeResources0 = LocalDefn (DirectOrRef ResourceDictP);

  others0 = pageTree.others0;
}

def NodeAddOther k pageTree : PageTreeNode0 = {
  type0 = pageTree.type0;
  parent0 = pageTree.parent0;
  kids0 = pageTree.kids0;
  count0 = pageTree.count0;
  nodeResources0 = pageTree.nodeResources0;

  others0 = Extend k (Token Value) pageTree.others0;
}

def PageTreeNodeRec (par : Ref) (cur : Ref) pageTree = Default pageTree 
  { @k = Token Name;
    @pageTree0 = if k == "Type" then {
        pageTree.type0 is false;
        AddType pageTree
      }
      else if k == "Parent" then {
        pageTree.parent0 is false;
        AddParent par pageTree
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
    PageTreeNodeRec par cur pageTree0
  }

def CheckKidsCount kids size = {
  @kidsCount = for (kidsCountAcc = 0; kid in kids)
    (kidsCountAcc + (pageNodeKidCount kid));
  Guard (size == kidsCount)
}

def ParseKidRefs (resrcs: maybe Pair) kidRefs cur = map (kidRef in kidRefs)
  (ParseAtRef kidRef (PageNodeKid resrcs cur kidRef))

-- PageTreeNode: coerce an partial page-tree node into a page
-- tree node
def PageTreeNode (cur : Ref) pt0 = {
  Guard pt0.type0;
  Guard pt0.parent0;
  kids = {
    @kidRefs = pt0.kids0 is just;
    ParseKidRefs pt0.nodeResources0 kidRefs cur
  };
  count = {
    $$ = pt0.count0 is just;
    CheckKidsCount kids $$
  };
  others = pt0.others0;
}

def PageTreeNodeP resrcs (par: Ref) (cur: Ref) = Between "<<" ">>" {
  @initPageTree = PageTreeNode0 (Inherit resrcs);
  @ptRec = PageTreeNodeRec par cur initPageTree;
  PageTreeNode cur ptRec
}

-- Parse the root of a page tree:

-- RootNode0: a partial page tree root value
def RootNode0 = {
  rootType0 = ^false;
  rootKids0 = ^nothing;
  rootCount0 = ^nothing;
  rootResources0 = ^nothing; 
  rootOthers0 = empty;
}

def RootAddType partialRoot : RootNode0 = {
  rootType0 = Holds (NameToken "Pages");

  rootKids0 = partialRoot.rootKids0;
  rootCount0 = partialRoot.rootCount0;
  rootResources0 = partialRoot.rootResources0;
  rootOthers0 = partialRoot.rootOthers0;
}

def RootAddKids partialRoot : RootNode0 = {
  rootType0 = partialRoot.rootType0;

  rootKids0 = just (GenArray Ref);

  rootCount0 = partialRoot.rootCount0;
  rootResources0 = partialRoot.rootResources0;
  rootOthers0 = partialRoot.rootOthers0;
}

def RootAddCount partialRoot : RootNode0 = {
  rootType0 = partialRoot.rootType0;
  rootKids0 = partialRoot.rootKids0;

  rootCount0 = just (DirectOrRef Natural);

  rootResources0 = partialRoot.rootResources0;
  rootOthers0 = partialRoot.rootOthers0;
}

def RootAddResources partialRoot : RootNode0 = {
  rootType0 = partialRoot.rootType0;
  rootKids0 = partialRoot.rootKids0;
  rootCount0 = partialRoot.rootCount0;

  rootResources0 = LocalDefn (DirectOrRef ResourceDictP);

  rootOthers0 = partialRoot.rootOthers0;
}

def RootAddOther k partialRoot : RootNode0 = {
  rootType0 = partialRoot.rootType0;
  rootKids0 = partialRoot.rootKids0;
  rootCount0 = partialRoot.rootCount0;
  rootResources0 = partialRoot.rootResources0;

  rootOthers0 = {
    @v = Token Value;
    Extend k v partialRoot.rootOthers0
  };
}

def PageTreeRootRec partialRoot = Default partialRoot {
  @k = Token Name;
  @partialRoot0 = if k == "Type" then {
      partialRoot.rootType0 is false;
      RootAddType partialRoot;
    }
    else if k == "Parent" then Void
    else if k == "Kids" then {
      partialRoot.rootKids0 is nothing;
      RootAddKids partialRoot;
    }
    else if k == "Count" then {
      partialRoot.rootCount0 is nothing;
      RootAddCount partialRoot;
    }
    else if k == "Resources" then {
      CheckNoLocalDefn partialRoot.rootResources0;
      RootAddResources partialRoot;
    }
    else RootAddOther k partialRoot;
  PageTreeRootRec partialRoot0
}

-- RootNode: coerce a partial root node into a root node
def RootNode (cur : Ref) partialRoot = {
  Guard partialRoot.rootType0;
  rootResources = partialRoot.rootResources0;
  rootKids = {
    @kidRefs = partialRoot.rootKids0 is just;
    ParseKidRefs rootResources kidRefs cur
  };
  rootCount = {
    $$ = partialRoot.rootCount0 is just;
    CheckKidsCount rootKids $$
  };
  rootOthers = partialRoot.rootOthers0;
}

def PageTreeP (cur : Ref) = Between "<<" ">>" {
  @initRoot = RootNode0;
  @partialRoot = PageTreeRootRec initRoot;
  RootNode cur partialRoot
}

-- TODO: check for cycles when building page tree
