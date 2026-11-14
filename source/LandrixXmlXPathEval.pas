{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Evaluates compiled XPath expressions (LandrixXmlXPath) on a tree
  (LandrixXmlXPathTree) as Saxon HE does without a schema: every node's
  typed value is xs:untypedAtomic, which becomes xs:double in arithmetic
  and in comparisons with numbers and xs:string in comparisons with
  strings; decimal division follows Saxon's scale rule
  (LandrixXmlDecimal); doubles are computed in software (LandrixXmlDouble)
  and written as Saxon writes them; strings are compared by code point;
  fn:upper-case and fn:lower-case map as Saxon does (U+00DF becomes SS;
  the table is generated from Saxon).

  Two profiles (TLandrixXmlXPathStaticContext.Profile, kept by every
  compiled expression): xppXPath20 follows XPath 2.0 and XML Schema 1.0
  where Saxon applies XPath 3.1 rules; xppSaxon behaves as Saxon HE 12
  does in the KoSIT validator (LandrixXmlSchematron uses it). The tested
  differences are listed in tests/data/xpath/profiles.txt.

  Like Saxon the evaluator does not evaluate what it does not need: "and"
  and "or" decide on either operand (an error in one operand does not
  matter if the other decides), variables are evaluated when first used,
  "if" evaluates one branch, "some" and "every" stop at the first decisive
  item. Dynamic errors raise ELandrixXmlXPathError with the W3C code
  (FORG0001 invalid cast, XPTY0004 type error, FOAR0001 division by zero,
  FORX0003 regex matching the empty string, ...).

  Variables: the slots of the static context are bound before an
  expression is evaluated (BindValue, or BindLazy for an expression that
  is evaluated on first use); slots below GlobalCount are shared by all
  frames (global variables), the others belong to the current frame (the
  variables of a Schematron rule, or the parameters and local variables
  of a user function). for, some and every use slots of their own.

  Not supported (a dynamic error XPST0017 or FOER0000, never a wrong
  value): ranges ("to") of more than 10,000,000 items (FOAR0002;
  Saxon would stream them), the year 0000 (XML Schema 1.0). Unlike Saxon
  the binding sequence of for, some and every is evaluated before the
  first item is used, so an error in a later item is raised even if an
  earlier one decides. Errors of the number units (an exponent out of
  range) are raised as FOAR0002 or FOCA0002. Dates follow XML Schema 1.0
  as LandrixXmlXsdTypes reads them (time zones up to 14:00, any number of
  fraction digits), where Saxon accepts more and keeps nanoseconds.
  fn:round and fn:round-half-to-even round large integers exactly
  (Saxon goes through xs:double there).

  An evaluator keeps the value of every subexpression that depends
  neither on the focus (context item, position, size) nor on current()
  nor on a variable other than a global one, such as an absolute path or
  count(//x): it is computed once per evaluator, as the rule sets ask for
  the same totals on every line of an invoice. Binding a global variable
  or SetGlobalCount drops the kept values; ClearCache too, which is needed
  only when the tree is loaded again while the evaluator lives.
  A child step name[@attribute = value] whose value does not depend on
  the focus (the code lists of the rule sets) goes through an index of
  the parent's children by that attribute, built on first use; it
  depends only on the trees, ClearCache and AddDocument drop it.

  Further documents: AddDocument gives document(Uri) a tree (the XSLT
  function, with the URI as the only argument, as Schematron rules use it
  for code lists). The nodes of all trees are numbered in one space: the
  evaluator's tree first, then each added tree from its base on; "/" and
  root() give the root of the node's own tree. Kept values of rooted
  paths hold for the evaluator's tree; from a node of an added tree they
  are computed again. AddTree adds a tree without a URI (the temporary
  trees of XSLT): it only gets node numbers after those already given,
  nothing kept is forgotten, so it is cheap enough for every constructed
  value.

  EvaluatePattern evaluates a path as the nodes an XSLT match pattern
  matches: a dynamic error in a predicate of one of its steps means that
  the item does not match (XSLT 3.0, 5.5.4), so the other items are kept.
  Later predicates that may use the position count as in Saxon (see
  ApplyPredicates): a[p][1] is still the first item when it comes before
  the failing one, a[p][last()] matches nothing. Saxon may stop early for
  position(): a[p][position() < 3] can still match before the failure
  there, here it does not. In a union a node one branch failed on does
  not match a later branch (Saxon tries them in order); only a failure on
  the branch's last step counts for that, not one on a step above it.
  Errors inside such a predicate (in a nested path) are not caught below
  it. Not caught at all: a circular variable (XTDE0640) and what is not
  supported (FOER0000, XPST0017), which must stay visible. The path is
  evaluated as given: a Schematron context must already be written as
  the nodes it selects (//a for the pattern a). }

unit LandrixXmlXPathEval;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlDecimal,
  LandrixXmlDouble,
  Contnrs,
  LandrixXmlRegex,
  LandrixXmlUnicode,
  LandrixXmlNormalize,
  LandrixXmlXsdTypes,
  LandrixXmlXPathTree,
  LandrixXmlXPath;

type
  { The value an item refers to (the digits of an xs:decimal or of an
    xs:integer beyond Int64, a date). It never changes once made, so
    items, copies of sequences and threads share it. }
  ILandrixXmlXPathValue = interface
    function Instance: TObject;
  end;

  { An item: a node of the tree (Node) or an atomic value. Internal, public
    because the evaluator's records need it; read the values through the
    evaluator, the layout changes with the supported types. }
  TLandrixXmlXPathItem = record
    Kind: TLandrixXmlXPathItemKind;
    Node: Integer;
    { xs:double: the bit pattern; xs:boolean: 0 or 1; xs:integer: the
      value if it fits (Payload nil) }
    Bits: Int64;
    { strings, untypedAtomic, anyURI, and the lexical form of dates }
    Text: TLandrixXmlUtf8;
    { xs:decimal, a large xs:integer, dates }
    Payload: ILandrixXmlXPathValue;
  end;
  TLandrixXmlXPathItems = array of TLandrixXmlXPathItem;

  TLandrixXmlXPathSequence = record
    Items: TLandrixXmlXPathItems;
    Count: Integer;
  end;

  { The focus of an evaluation: a context node (Node, Item empty), an
    atomic context item (Node -1, Item one item) or none (Node -1, Item
    empty, Position and Size 0); Position from 1 to Size otherwise. }
  TLandrixXmlXPathFocus = record
    Node: Integer;
    Item: TLandrixXmlXPathSequence;
    Position: Integer;
    Size: Integer;
  end;

  TLandrixXmlXPathEvaluator = class;
  TLandrixXmlXPathFunctionDef = class;

  { A user function implemented by the caller (for the XSLT units, not
    part of the documented API yet): the arguments are evaluated (not
    converted to the parameter types), Focus is the caller's, and
    current() keeps the caller's node (unlike in a user function with a
    body). It may evaluate other expressions with the evaluator (they
    share the current frame of variables); it raises
    ELandrixXmlXPathError for a dynamic error. }
  TLandrixXmlXPathHostFunction = function(Evaluator: TLandrixXmlXPathEvaluator; Def: TLandrixXmlXPathFunctionDef;
    const Args: array of TLandrixXmlXPathSequence; const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence of object;

  TLandrixXmlXPathSlotState = (xssUnbound, xssValue, xssLazy, xssEvaluating, xssError);

  TLandrixXmlXPathSlot = record
    State: TLandrixXmlXPathSlotState;
    Value: TLandrixXmlXPathSequence;
    Expression: TLandrixXmlXPathExpression;
    ContextNode: Integer;
    ErrorCode: string;
    ErrorMessage: string;
    { the error came from fn:error }
    ErrorRaised: Boolean;
    { the declared type the value is converted to (xsl:variable as=) }
    DeclaredType: TLandrixXmlXPathSequenceType;
  end;
  TLandrixXmlXPathSlots = array of TLandrixXmlXPathSlot;

  { A user function: parameters and local variables are slots of the
    static context its expressions were compiled with (whose first
    GlobalCount variables are the globals); locals are evaluated lazily,
    the body gives the result. Owned by the caller. }
  TLandrixXmlXPathFunctionDef = class
  public
    ParamSlots: array of Integer;
    ParamTypes: array of TLandrixXmlXPathSequenceType;
    LocalSlots: array of Integer;
    LocalExpressions: array of TLandrixXmlXPathExpression;
    LocalTypes: array of TLandrixXmlXPathSequenceType;
    Body: TLandrixXmlXPathExpression;
    ResultType: TLandrixXmlXPathSequenceType;
    { the number of variables of the function's static context }
    FrameSize: Integer;
    Name: string;
    { set: the function is the caller's, Body and the slots are not used
      (see TLandrixXmlXPathHostFunction); Tag is the caller's }
    Host: TLandrixXmlXPathHostFunction;
    Tag: Integer;
  end;

  TLandrixXmlXPathTreeArray = array of TLandrixXmlXPathTree;

  { The result of Evaluate. }
  TLandrixXmlXPathResult = class
  private
    FItems: TLandrixXmlXPathSequence;
    FTree: TLandrixXmlXPathTree;
    { the trees AddDocument and AddTree gave the evaluator and their bases
      (the first FDocCount entries) }
    FDocTrees: TLandrixXmlXPathTreeArray;
    FDocBases: TLandrixXmlXPathIntArray;
    FDocCount: Integer;
    function GetCount: Integer;
    function GetKind(Index: Integer): TLandrixXmlXPathItemKind;
    function GetNode(Index: Integer): Integer;
  public
    property Count: Integer read GetCount;
    property Kind[Index: Integer]: TLandrixXmlXPathItemKind read GetKind;
    { the node of a node item (an index into the tree; from Tree.Count on a
      node of a document added with AddDocument), -1 for atomic values }
    property Node[Index: Integer]: Integer read GetNode;
    { the string value of the item (fn:string) }
    function StringValueUtf8(Index: Integer): TLandrixXmlUtf8;
    { the XPath type name: xs:string, xs:decimal, ...; node() for nodes }
    function TypeName(Index: Integer): string;
    { the effective boolean value of the whole result }
    function AsBoolean: Boolean;
  end;

  TLandrixXmlXPathEvaluator = class
  private
    FTree: TLandrixXmlXPathTree;
    { AddDocument and AddTree: the URIs, trees and the first node number
      of each (the first FDocCount entries; the arrays grow by doubling);
      FDocNamed: added with AddDocument (AddTree's have no URI) }
    FDocUris: TLandrixXmlUtf8Array;
    FDocTrees: TLandrixXmlXPathTreeArray;
    FDocBases: TLandrixXmlXPathIntArray;
    FDocNamed: array of Boolean;
    FDocCount: Integer;
    FGlobalCount: Integer;
    FGlobals: TLandrixXmlXPathSlots;
    FFrame: TLandrixXmlXPathSlots;
    { PushFrame: the frames below the current one }
    FFrameStack: array of TLandrixXmlXPathSlots;
    FFrameTop: Integer;
    { slots of for, some and every: a stack, one block per expression being evaluated }
    FLocals: array of TLandrixXmlXPathSequence;
    FLocalTop: Integer;
    FFunctions: TList;
    FCurrentNode: Integer;
    FDepth: Integer;
    FMaxDepth: Integer;
    { the implicit time zone and the current dateTime (FHasClock: read
      or set) }
    FImplicitTimeZone: Integer;
    FClock: TLandrixXmlXsdDateTime;
    FHasClock: Boolean;
    { compiled patterns: the dialect ("2" or "3"), flags, #0, the pattern (UTF-8) and the regex }
    FRegexKeys: TLandrixXmlUtf8Array;
    FRegexes: TObjectList;
    { the expression being evaluated and the base of its local slots }
    FExpr: TLandrixXmlXPathExpression;
    FNodes: TLandrixXmlXPathAstNodes;
    FLocalBase: Integer;
    { kept values of context-free subexpressions: one entry per expression
      (owned by FCaches, found by FCacheTable), FCache that of FExpr }
    FCaches: TObjectList;
    FCacheTable: array of TObject;
    FCache: TObject;
    { the node being computed for its entry, so that Eval does not look again }
    FBypass: Integer;
    { the indexes of the steps "name[@attribute = value]" (TKeyIndex, owned
      by FKeyIndexes, found by FKeyTable); forgotten with the node numbers }
    FKeyIndexes: TObjectList;
    FKeyTable: array of TObject;
    { EnterExpression calls not yet left }
    FNesting: Integer;
    { EvaluatePattern: the predicates of the steps being evaluated drop the
      items they fail on; FFinal while the last step of a branch is
      evaluated, whose failed items FFailed lists (a later branch of a
      union must not match them) }
    FPattern: Boolean;
    FFinal: Boolean;
    FFailed: array of Integer;
    FFailedCount: Integer;
    { the first node from which a pattern's positions are still unknown
      after the predicates evaluated so far (MaxInt if none) }
    FMinFailed: Integer;
    procedure SetImplicitTimeZone(Value: Integer);
    procedure SetCurrentDateTime(const Value: TLandrixXmlXsdDateTime);
    function GetCurrentDateTime: TLandrixXmlXsdDateTime;
    procedure ResetDynamicContext;
    function ClockItem(Kind: TLandrixXmlXPathItemKind): TLandrixXmlXPathItem;
    procedure CutAfterFailure(var S: TLandrixXmlXPathSequence; FailAt: Integer; All, Final: Boolean);
    procedure AddFailed(Node: Integer);
    function WithoutFailed(const S: TLandrixXmlXPathSequence; First, Last: Integer): TLandrixXmlXPathSequence;
    function FindCache(Expr: TLandrixXmlXPathExpression): TObject;
    function CachedEval(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    procedure DropCachedValues;
    procedure DropKeyIndexes;
    function FindKeyIndex(Parent, ChildName, AttributeName: Integer): TObject;
    function KeyedStep(Index, Node: Integer; var Output: TLandrixXmlXPathSequence): Boolean;
    { EvaluateSequence without the copy, for read-only use }
    function EvaluateShared(Expr: TLandrixXmlXPathExpression; ContextNode: Integer): TLandrixXmlXPathSequence;
    procedure EnterExpression(Expr: TLandrixXmlXPathExpression; out SavedExpr: TLandrixXmlXPathExpression;
      out SavedBase: Integer);
    procedure LeaveExpression(SavedExpr: TLandrixXmlXPathExpression; SavedBase: Integer);
    procedure ComputeBases;
    procedure AppendTree(const Uri: TLandrixXmlUtf8; Tree: TLandrixXmlXPathTree; Named: Boolean);
    function TreeOf(Node: Integer; out Base: Integer): TLandrixXmlXPathTree;
    function NodeMatches(Node: Integer; const T: TLandrixXmlXPathSequenceType): Boolean;
    function SequenceMatches(const S: TLandrixXmlXPathSequence; const T: TLandrixXmlXPathSequenceType): Boolean;
    function RootOf(Node: Integer): Integer;
    { RootOf for "/": XPDY0050 if the root is no document node }
    function DocumentRootOf(Node: Integer): Integer;
    function SlotRef(Slot: Integer): Pointer;
    function ReadVariable(Slot: Integer): TLandrixXmlXPathSequence;
    procedure WriteLocal(Slot: Integer; const Value: TLandrixXmlXPathSequence);
    function Eval(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    procedure EvalInto(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure EvalLiteral(Index: Integer; var Output: TLandrixXmlXPathSequence);
    procedure ReadVariableInto(Slot: Integer; var Output: TLandrixXmlXPathSequence);
    procedure NodeItemInto(Node: Integer; var Output: TLandrixXmlXPathSequence);
    procedure StepInto(Index: Integer; Node: Integer; Axis: TLandrixXmlXPathAxis;
      var Output: TLandrixXmlXPathSequence);
    procedure CachedInto(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure PathInto(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure IntersectExceptInto(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure CallBooleanFunction(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure CallStringFunction(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure CallContextSeq(Id: TLandrixXmlXPathFunctionId; Context: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    function CallStrArg(Index, K: Integer; Context, Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlUtf8;
    procedure CallFunctionInto(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure EvalSequenceExpr(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure EvalFilter(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure EvalForSomeEvery(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure EvalIf(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure EvalAndOr(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure EvalGeneralCompare(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure EvalOperator(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure EvalUnion(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure EvalNodeCompare(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure EvalInstanceTreat(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    procedure EvalCast(Index: Integer; Context: Integer; Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
    function EvalStep(Index: Integer; Node: Integer; Axis: TLandrixXmlXPathAxis): TLandrixXmlXPathSequence;
    function EvalIntersectExcept(Index: Integer; Context, Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function EvalPath(Index: Integer; Context, Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function ApplyPredicates(const Predicates: array of Integer;
      const Input: TLandrixXmlXPathSequence; InputFailedAt: Integer): TLandrixXmlXPathSequence;
    function EvalQuantified(Index, Binding: Integer; Context, Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence; Kind: TLandrixXmlXPathAstKind;
      var Output: TLandrixXmlXPathSequence): Boolean;
    function CallFunction(Index: Integer; Context, Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function CallUser(Def: TLandrixXmlXPathFunctionDef; const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function CallHost(Def: TLandrixXmlXPathFunctionDef; const Args: array of TLandrixXmlXPathSequence;
      Context, Position, Size: Integer; const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function EvaluateFocusShared(Expr: TLandrixXmlXPathExpression; Context, Position, Size: Integer;
      const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function Regex(const Pattern, Flags: TLandrixXmlUtf8): TLandrixXmlRegex;
    function StringOf(const Item: TLandrixXmlXPathItem): TLandrixXmlUtf8;
    { the expression being evaluated was compiled for XPath 2.0 (not the
      Saxon profile) }
    function Xp20: Boolean;
    function Atomize(const S: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    { AsXPath20: the profile of the definition the type belongs to (the
      function, the variable), not that of the caller }
    function ConvertTo(const S: TLandrixXmlXPathSequence; const T: TLandrixXmlXPathSequenceType;
      const FunctionName: string; AsXPath20: Boolean): TLandrixXmlXPathSequence;
  public
    { The tree is not owned. }
    constructor Create(Tree: TLandrixXmlXPathTree);
    destructor Destroy; override;
    { Evaluates Expr with the node ContextNode as context item (position 1,
      size 1). The caller frees the result. }
    function Evaluate(Expr: TLandrixXmlXPathExpression; ContextNode: Integer): TLandrixXmlXPathResult;
    function EvaluateBoolean(Expr: TLandrixXmlXPathExpression; ContextNode: Integer): Boolean;
    { the string values of the items joined with spaces (xsl:value-of) }
    function EvaluateString(Expr: TLandrixXmlXPathExpression; ContextNode: Integer): TLandrixXmlUtf8;
    function EvaluateSequence(Expr: TLandrixXmlXPathExpression; ContextNode: Integer): TLandrixXmlXPathSequence;
    { EvaluateSequence with any focus (see TLandrixXmlXPathFocus; for the
      XSLT units, not part of the documented API yet); an invalid focus
      raises ELandrixXmlError (xecInvalidArgument) }
    function EvaluateInFocus(Expr: TLandrixXmlXPathExpression;
      const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
    { EvaluateSequence as an XSLT match pattern (see the unit comment); Expr
      is the path of the matched nodes (//a for the pattern a) }
    function EvaluatePattern(Expr: TLandrixXmlXPathExpression; ContextNode: Integer): TLandrixXmlXPathSequence;
    { True if Node is one of the nodes EvaluatePattern(Expr, root of Node)
      returns (for the XSLT units, not part of the documented API yet):
      decided from the node upwards when Expr is a path of child and
      attribute steps and "//" (the predicates of a step are evaluated on
      the node's siblings), otherwise and after a dynamic error through
      EvaluatePattern. A predicate that cannot read the position is
      evaluated for the node alone: a dynamic error in it means no match.
      Relative: Expr is "//" followed by a relative pattern (the caller
      gives patterns starting with "/" or document-node() as rooted
      paths); then a node without parent matches the first step, as in
      XSLT 3.0. In a tree without document node a pattern that needs
      EvaluatePattern (a positional predicate with a dynamic error, a
      function at the start) does not match. current() is CurrentNode,
      as the caller sets it. }
    function MatchesPattern(Expr: TLandrixXmlXPathExpression; Node: Integer; Relative: Boolean): Boolean;
    { Helpers for the XSLT units (not part of the documented API yet): the
      string value of an item (fn:string), the effective boolean value of
      a sequence (FORG0006), the function conversion rules to a declared
      type (as in the Saxon profile; Name for messages), the tree of a
      node and the number its nodes start from. }
    function ItemString(const Item: TLandrixXmlXPathItem): TLandrixXmlUtf8;
    function EffectiveBoolean(const S: TLandrixXmlXPathSequence): Boolean;
    function ConvertSequence(const S: TLandrixXmlXPathSequence; const T: TLandrixXmlXPathSequenceType;
      const Name: string): TLandrixXmlXPathSequence;
    function TreeOfNode(Node: Integer; out Base: Integer): TLandrixXmlXPathTree;
    { Variables: slots below GlobalCount are global; the others belong to
      the current frame. Setting GlobalCount or FrameSize unbinds the slots
      concerned. }
    procedure SetGlobalCount(Count: Integer);
    procedure SetFrameSize(Size: Integer);
    procedure BindValue(Slot: Integer; const Value: TLandrixXmlXPathSequence);
    procedure BindString(Slot: Integer; const Value: TLandrixXmlUtf8);
    { evaluated on first use with ContextNode as context item }
    procedure BindLazy(Slot: Integer; Expr: TLandrixXmlXPathExpression; ContextNode: Integer);
    { BindLazy, the value converted to T when it is evaluated (an XSLT
      variable with "as"; for the XSLT units, not part of the documented
      API yet) }
    procedure BindLazyAs(Slot: Integer; Expr: TLandrixXmlXPathExpression; ContextNode: Integer;
      const T: TLandrixXmlXPathSequenceType);
    procedure UnbindFrame;
    { A new frame of Size unbound slots for a call (an XSLT template or
      stylesheet function; for the XSLT units, not part of the documented
      API yet); PopFrame returns to the frame before it. Globals and kept
      values are not touched. The caller pops in a finally block. }
    procedure PushFrame(Size: Integer);
    procedure PopFrame;
    { forgets the kept values of context-free subexpressions (see the unit
      comment); needed when the tree changes while the evaluator lives }
    procedure ClearCache;
    { the tree document(Uri) returns (the URI as written in the expression),
      which has a document node; not owned, it must live as long as the
      evaluator and its results }
    procedure AddDocument(const Uri: TLandrixXmlUtf8; Tree: TLandrixXmlXPathTree);
    { A tree without URI (a temporary tree of XSLT, with or without a
      document node; for the XSLT units, not part of the documented API
      yet); returns the number of its node 0. The node numbers given so
      far and the kept values stay (until ClearCache, which numbers all
      trees again). Not owned: it must live as long as
      the evaluator and the values that hold its nodes. }
    function AddTree(Tree: TLandrixXmlXPathTree): Integer;
    { user functions (TLandrixXmlXPathFunctionDef) by their index in the
      static context; not owned }
    property Functions: TList read FFunctions write FFunctions;
    { the node fn:current() returns (the context node of a Schematron rule) }
    property CurrentNode: Integer read FCurrentNode write FCurrentNode;
    property Tree: TLandrixXmlXPathTree read FTree;
    { the maximum nesting of user function calls (default 500) }
    property MaxDepth: Integer read FMaxDepth write FMaxDepth;
    { The implicit time zone in minutes east of UTC (-840 to 840; default
      0, UTC): values without a time zone are compared with and
      subtracted from others in it, and current-dateTime() has it. }
    property ImplicitTimeZone: Integer read FImplicitTimeZone write SetImplicitTimeZone;
    { What current-dateTime(), current-date() and current-time() return
      (with the implicit time zone: a value with a time zone is adjusted
      to it, one without gets it); a value that is not a valid date and
      time (hour 0 to 23) raises ELandrixXmlError. If it is not set, SysUtils.Now is read
      at the first use and kept for the evaluator's lifetime; Now is the
      local clock, so that value is the right instant only if
      ImplicitTimeZone is the local offset. Reading the property before
      the first use reads the clock. }
    property CurrentDateTime: TLandrixXmlXsdDateTime read GetCurrentDateTime write SetCurrentDateTime;
    { forgets a CurrentDateTime set before: the clock is read again }
    procedure ClearCurrentDateTime;
  end;

{ The empty sequence and single items. }
function LandrixXmlXPathEmpty: TLandrixXmlXPathSequence;
function LandrixXmlXPathStringItem(const S: TLandrixXmlUtf8): TLandrixXmlXPathSequence;
function LandrixXmlXPathNodeItem(Node: Integer): TLandrixXmlXPathSequence;
procedure LandrixXmlXPathAppend(var S: TLandrixXmlXPathSequence; const Item: TLandrixXmlXPathItem);
{ Relative resolved against Base (RFC 3986, as fn:resolve-uri; an
  absolute Relative stays as it is); for the XSLT units, not part of the
  documented API yet. }
function LandrixXmlXPathResolveUri(const Relative, Base: TLandrixXmlUtf8): TLandrixXmlUtf8;
{ The base URI of node Node of Tree (as fn:base-uri: xml:base included),
  False for none; for the XSLT units, not part of the documented API yet. }
function LandrixXmlXPathNodeBaseUri(Tree: TLandrixXmlXPathTree; Node: Integer; out Uri: TLandrixXmlUtf8): Boolean;

implementation

{$I LandrixXmlCaseData.inc}

type
  PSlot = ^TLandrixXmlXPathSlot;

  { The kept values of one expression: Flags marks the outermost
    context-free subexpressions worth keeping. }
  TExpressionCache = class
  public
    Expression: TLandrixXmlXPathExpression;
    Serial: Int64;
    Flags: array of Boolean;
    Have: array of Boolean;
    Values: array of TLandrixXmlXPathSequence;
    { a child step whose predicates do not depend on the position: after
      descendant-or-self::node() ("//") it is evaluated as descendant }
    Fuse: array of Boolean;
    { the value is that of the evaluator's own tree (a rooted path): from a
      node of another tree it is computed without being kept }
    RootOnly: array of Boolean;
    { a child step whose first predicate is "@attribute = value" with a
      value that does not depend on the focus: the attribute step and the
      value (-1 if the step is not one) }
    KeyAttribute: array of Integer;
    KeyValue: array of Integer;
  end;

  { The element children of one parent with one name, by the value of one
    of their attributes (see KeyedStep). Children without the attribute
    are not in it. }
  TKeyIndex = class
  public
    { the parent (node number) and the expanded names in its tree }
    Parent: Integer;
    ChildName: Integer;
    AttributeName: Integer;
    { False: too few children, the step is evaluated as usual }
    Indexed: Boolean;
    { the distinct values: the first and the last child with Values[K]
      (positions in Nodes); Marks for KeyedStep }
    Values: array of TLandrixXmlUtf8;
    FirstOf: array of Integer;
    LastOf: array of Integer;
    Marks: array of Boolean;
    ValueCount: Integer;
    { open addressing over Values: value index + 1, 0 = free }
    Table: array of Integer;
    { the children (node numbers) in document order; NextOf the position of
      the next child with the same value (-1 for none) }
    Nodes: array of Integer;
    NextOf: array of Integer;
    { the value's index (-1 if absent); Add: append it if absent }
    function Find(const Value: TLandrixXmlUtf8; Add: Boolean): Integer;
  end;

  { xdRoot: the root of the context node's tree ("/a") }
  TDependency = (xdFocus, xdOther, xdRoot);
  TDependencies = set of TDependency;

  { the payloads of items (ILandrixXmlXPathValue), never changed after
    construction }
  TDecimalValue = class(TInterfacedObject, ILandrixXmlXPathValue)
  public
    Value: TLandrixXmlDecimal;
    constructor Create(const AValue: TLandrixXmlDecimal);
    function Instance: TObject;
  end;

  TDateTimeValue = class(TInterfacedObject, ILandrixXmlXPathValue)
  public
    Value: TLandrixXmlXsdDateTime;
    constructor Create(const AValue: TLandrixXmlXsdDateTime);
    function Instance: TObject;
  end;

  { a duration: months and seconds with the same sign (the seconds with
    at most nine fraction digits) }
  TDurationValue = class(TInterfacedObject, ILandrixXmlXPathValue)
  public
    Months: Integer;
    Seconds: TLandrixXmlDecimal;
    constructor Create(AMonths: Integer; const ASeconds: TLandrixXmlDecimal);
    function Instance: TObject;
  end;

  { an xs:QName: namespace URI, prefix (may be empty) and local name; the
    item's text is the lexical form }
  TQNameValue = class(TInterfacedObject, ILandrixXmlXPathValue)
  public
    NamespaceUri: TLandrixXmlUtf8;
    Prefix: TLandrixXmlUtf8;
    LocalName: TLandrixXmlUtf8;
    constructor Create(const AUri, APrefix, ALocal: TLandrixXmlUtf8);
    function Instance: TObject;
  end;

procedure Fail(const Code, Msg: string);
begin
  raise ELandrixXmlXPathError.CreateXPath(Code, Msg);
end;

type
  { raised by fn:error: an error of the expression itself, also with the
    code FOER0000, which otherwise marks what is not supported }
  ELandrixXmlXPathRaised = class(ELandrixXmlXPathError);

{ --- sequences ---------------------------------------------------------- }

function LandrixXmlXPathEmpty: TLandrixXmlXPathSequence;
begin
  Result.Items := nil;
  Result.Count := 0;
end;

procedure LandrixXmlXPathAppend(var S: TLandrixXmlXPathSequence; const Item: TLandrixXmlXPathItem);
begin
  if S.Count = Length(S.Items) then
    SetLength(S.Items, 2 * S.Count + 4);
  S.Items[S.Count] := Item;
  Inc(S.Count);
end;

procedure AppendAll(var S: TLandrixXmlXPathSequence; const T: TLandrixXmlXPathSequence);
var
  I: Integer;
begin
  for I := 0 to T.Count - 1 do
    LandrixXmlXPathAppend(S, T.Items[I]);
end;

constructor TDecimalValue.Create(const AValue: TLandrixXmlDecimal);
begin
  inherited Create;
  Value := AValue;
end;

function TDecimalValue.Instance: TObject;
begin
  Result := Self;
end;

constructor TDateTimeValue.Create(const AValue: TLandrixXmlXsdDateTime);
begin
  inherited Create;
  Value := AValue;
end;

function TDateTimeValue.Instance: TObject;
begin
  Result := Self;
end;

constructor TDurationValue.Create(AMonths: Integer; const ASeconds: TLandrixXmlDecimal);
begin
  inherited Create;
  Months := AMonths;
  Seconds := ASeconds;
end;

function TDurationValue.Instance: TObject;
begin
  Result := Self;
end;

constructor TQNameValue.Create(const AUri, APrefix, ALocal: TLandrixXmlUtf8);
begin
  inherited Create;
  NamespaceUri := AUri;
  Prefix := APrefix;
  LocalName := ALocal;
end;

function TQNameValue.Instance: TObject;
begin
  Result := Self;
end;

procedure InitItem(out Item: TLandrixXmlXPathItem; Kind: TLandrixXmlXPathItemKind);
begin
  Item.Kind := Kind;
  Item.Node := -1;
  Item.Bits := 0;
  Item.Text := '';
  Item.Payload := nil;
end;

function SingleSeq(const Item: TLandrixXmlXPathItem): TLandrixXmlXPathSequence;
begin
  Result.Items := nil;
  SetLength(Result.Items, 1);
  Result.Items[0] := Item;
  Result.Count := 1;
end;

function LandrixXmlXPathNodeItem(Node: Integer): TLandrixXmlXPathSequence;
var
  Item: TLandrixXmlXPathItem;
begin
  InitItem(Item, xikNode);
  Item.Node := Node;
  Result := SingleSeq(Item);
end;

function StringItem(Kind: TLandrixXmlXPathItemKind; const S: TLandrixXmlUtf8): TLandrixXmlXPathItem;
begin
  InitItem(Result, Kind);
  Result.Text := S;
end;

function LandrixXmlXPathStringItem(const S: TLandrixXmlUtf8): TLandrixXmlXPathSequence;
begin
  Result := SingleSeq(StringItem(xikString, S));
end;

function BooleanItem(B: Boolean): TLandrixXmlXPathItem;
begin
  InitItem(Result, xikBoolean);
  Result.Bits := Ord(B);
end;

function BooleanSeq(B: Boolean): TLandrixXmlXPathSequence;
begin
  Result := SingleSeq(BooleanItem(B));
end;

function IntegerItem(const D: TLandrixXmlDecimal): TLandrixXmlXPathItem;
begin
  InitItem(Result, xikInteger);
  if not LandrixXmlDecimalTryToInt64(D, Result.Bits) then
  begin
    Result.Bits := 0;
    Result.Payload := TDecimalValue.Create(D);
  end;
end;

function IntegerItemOf(Value: Int64): TLandrixXmlXPathItem;
begin
  InitItem(Result, xikInteger);
  Result.Bits := Value;
end;

function DecimalItem(const D: TLandrixXmlDecimal): TLandrixXmlXPathItem;
begin
  InitItem(Result, xikDecimal);
  Result.Payload := TDecimalValue.Create(D);
end;

function DoubleItem(const D: TLandrixXmlDouble): TLandrixXmlXPathItem;
begin
  InitItem(Result, xikDouble);
  Result.Bits := D.Bits;
end;

{ An xs:QName from its parts. }
function QNameItem(const Uri, Prefix, LocalName: TLandrixXmlUtf8): TLandrixXmlXPathItem;
begin
  InitItem(Result, xikQName);
  Result.Payload := TQNameValue.Create(Uri, Prefix, LocalName);
  if Prefix = '' then
    Result.Text := LocalName
  else
    Result.Text := Prefix + ':' + LocalName;
end;

function ItemQName(const Item: TLandrixXmlXPathItem): TQNameValue;
begin
  Result := TQNameValue(Item.Payload.Instance);
end;

{ An xs:float: D rounded to the nearest binary32 value, kept as a double. }
function FloatItem(const D: TLandrixXmlDouble): TLandrixXmlXPathItem;
begin
  InitItem(Result, xikFloat);
  Result.Bits := LandrixXmlDoubleRoundToFloat(D).Bits;
end;

{ An xs:integer (Kind xikInteger) or xs:decimal. }
function DecimalKindItem(Kind: TLandrixXmlXPathItemKind; const D: TLandrixXmlDecimal): TLandrixXmlXPathItem;
begin
  if Kind = xikInteger then
    Result := IntegerItem(D)
  else
    Result := DecimalItem(D);
end;

{ An xs:date, xs:dateTime or xs:time with its lexical form. }
function DateItem(Kind: TLandrixXmlXPathItemKind; const D: TLandrixXmlXsdDateTime;
  const Text: TLandrixXmlUtf8): TLandrixXmlXPathItem;
begin
  InitItem(Result, Kind);
  Result.Payload := TDateTimeValue.Create(D);
  Result.Text := Text;
end;

{ An xs:duration, xs:yearMonthDuration or xs:dayTimeDuration with its
  lexical form (DurationText). }
function DurationValueItem(Kind: TLandrixXmlXPathItemKind; Months: Integer; const Seconds: TLandrixXmlDecimal;
  const Text: TLandrixXmlUtf8): TLandrixXmlXPathItem;
begin
  InitItem(Result, Kind);
  Result.Payload := TDurationValue.Create(Months, Seconds);
  Result.Text := Text;
end;

{ The values of items. Only InitItem, the constructors above and these
  functions use the value fields of an item. }

function ItemBoolean(const Item: TLandrixXmlXPathItem): Boolean;
begin
  Result := Item.Bits <> 0;
end;

{ the value of an xs:integer or xs:decimal }
function ItemDecimal(const Item: TLandrixXmlXPathItem): TLandrixXmlDecimal;
begin
  if Item.Payload = nil then
    Result := LandrixXmlDecimalFromInt64(Item.Bits)
  else
    Result := TDecimalValue(Item.Payload.Instance).Value;
end;

function ItemDouble(const Item: TLandrixXmlXPathItem): TLandrixXmlDouble;
begin
  Result.Bits := Item.Bits;
end;

{ the value of an xs:date, xs:dateTime or xs:time }
function ItemDateTime(const Item: TLandrixXmlXPathItem): TLandrixXmlXsdDateTime;
begin
  Result := TDateTimeValue(Item.Payload.Instance).Value;
end;

{ the months and seconds of a duration }
function ItemMonths(const Item: TLandrixXmlXPathItem): Integer;
begin
  Result := TDurationValue(Item.Payload.Instance).Months;
end;

function ItemSeconds(const Item: TLandrixXmlXPathItem): TLandrixXmlDecimal;
begin
  Result := TDurationValue(Item.Payload.Instance).Seconds;
end;

const
  { xs:integer and the types derived from it }
  IntegerKinds = [xikInteger, xikNonPositiveInteger .. xikPositiveInteger];
  { xs:string and the types derived from it }
  StringKinds = [xikString, xikNormalizedString .. xikENTITY];
  { xs:gYearMonth, xs:gYear, xs:gMonthDay, xs:gDay, xs:gMonth }
  GregorianKinds = [xikGYearMonth .. xikGMonth];
  BinaryKinds = [xikHexBinary, xikBase64Binary];
  DurationKinds = [xikDuration, xikYearMonthDuration, xikDayTimeDuration];

{ The kind an operation sees: xs:integer and xs:string for the types
  derived from them. }
function BasicKind(Kind: TLandrixXmlXPathItemKind): TLandrixXmlXPathItemKind;
begin
  if Kind in IntegerKinds then
    Result := xikInteger
  else if Kind in StringKinds then
    Result := xikString
  else
    Result := Kind;
end;

function IsNumeric(Kind: TLandrixXmlXPathItemKind): Boolean;
begin
  Result := Kind in IntegerKinds + [xikDecimal, xikDouble, xikFloat];
end;

function IsStringLike(Kind: TLandrixXmlXPathItemKind): Boolean;
begin
  Result := Kind in StringKinds + [xikUntypedAtomic, xikAnyUri];
end;

function KindName(Kind: TLandrixXmlXPathItemKind): string;
begin
  Result := LandrixXmlXPathAtomicTypeName(Kind);
end;

{ --- string helpers (code points) ----------------------------------------- }

function CodePointLength(const S: TLandrixXmlUtf8): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) do
    if (Ord(S[I]) and $C0) <> $80 then
      Inc(Result);
end;

{ The byte position (1-based) of code point N (1-based) in S; Length + 1
  after the end. }
function BytePosition(const S: TLandrixXmlUtf8; N: Integer): Integer;
var
  K: Integer;
begin
  Result := 1;
  K := 1;
  while (Result <= Length(S)) and (K < N) do
  begin
    Inc(Result);
    while (Result <= Length(S)) and ((Ord(S[Result]) and $C0) = $80) do
      Inc(Result);
    Inc(K);
  end;
end;

function NormalizeSpace(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I, N: Integer;
  Space: Boolean;
begin
  Result := '';
  SetLength(Result, Length(S));
  N := 0;
  Space := False;
  for I := 1 to Length(S) do
    if S[I] in [' ', #9, #10, #13] then
      Space := N > 0
    else
    begin
      if Space then
      begin
        Inc(N);
        Result[N] := ' ';
        Space := False;
      end;
      Inc(N);
      Result[N] := S[I];
    end;
  SetLength(Result, N);
end;

function Trimmed(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  A, B: Integer;
begin
  A := 1;
  B := Length(S);
  while (A <= B) and (S[A] in [' ', #9, #10, #13]) do
    Inc(A);
  while (B >= A) and (S[B] in [' ', #9, #10, #13]) do
    Dec(B);
  Result := Copy(S, A, B - A + 1);
end;

function MapCase(const S: TLandrixXmlUtf8; Upper: Boolean): TLandrixXmlUtf8;
var
  CPs: TLandrixXmlCodePoints;
  I, Lo, Hi, Mid, Key, Count, Start, Stop: Integer;
  Buf: TLandrixXmlUtf8;
  Ascii: Boolean;
begin
  CPs := nil;
  { ASCII only: no table }
  Ascii := True;
  for I := 1 to Length(S) do
    if Ord(S[I]) >= $80 then
    begin
      Ascii := False;
      Break;
    end;
  if Ascii then
  begin
    Result := S;
    for I := 1 to Length(Result) do
      if Upper and (Result[I] in ['a'..'z']) then
        Result[I] := AnsiChar(Ord(Result[I]) - 32)
      else if not Upper and (Result[I] in ['A'..'Z']) then
        Result[I] := AnsiChar(Ord(Result[I]) + 32);
    Exit;
  end;
  CPs := LandrixXmlUtf8ToCodePoints(S);
  Result := '';
  if Upper then
    Count := UpperCaseCount
  else
    Count := LowerCaseCount;
  for I := 0 to Integer(Length(CPs)) - 1 do
  begin
    Lo := 0;
    Hi := Count - 1;
    Mid := -1;
    while Lo <= Hi do
    begin
      Mid := (Lo + Hi) div 2;
      if Upper then
        Key := UpperCaseKeys[Mid]
      else
        Key := LowerCaseKeys[Mid];
      if Key = CPs[I] then
        Break;
      if Key < CPs[I] then
        Lo := Mid + 1
      else
        Hi := Mid - 1;
      Mid := -1;
    end;
    if Mid < 0 then
    begin
      Buf := '';
      SetLength(Buf, 4);
      SetLength(Buf, LandrixXmlEncodeUtf8(Cardinal(CPs[I]), PAnsiChar(Buf)));
      Result := Result + Buf;
    end
    else
    begin
      if Upper then
      begin
        Start := UpperCaseStarts[Mid];
        Stop := UpperCaseStarts[Mid + 1];
      end
      else
      begin
        Start := LowerCaseStarts[Mid];
        Stop := LowerCaseStarts[Mid + 1];
      end;
      Buf := '';
      SetLength(Buf, Stop - Start);
      for Key := Start to Stop - 1 do
        if Upper then
          Buf[Key - Start + 1] := AnsiChar(UpperCasePool[Key])
        else
          Buf[Key - Start + 1] := AnsiChar(LowerCasePool[Key]);
      Result := Result + Buf;
    end;
  end;
end;

{ --- TLandrixXmlXPathResult ------------------------------------------------ }

function TLandrixXmlXPathResult.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TLandrixXmlXPathResult.GetKind(Index: Integer): TLandrixXmlXPathItemKind;
begin
  Result := FItems.Items[Index].Kind;
end;

function TLandrixXmlXPathResult.GetNode(Index: Integer): Integer;
begin
  Result := FItems.Items[Index].Node;
end;

function TLandrixXmlXPathResult.TypeName(Index: Integer): string;
begin
  Result := KindName(FItems.Items[Index].Kind);
end;

{$I LandrixXmlXPathCast.inc}

{ The tree of Node in the numbering of TLandrixXmlXPathEvaluator.AddDocument
  and the number its nodes start from (the bases of the first Count trees
  ascend). }
function NodeTree(Main: TLandrixXmlXPathTree; const Trees: TLandrixXmlXPathTreeArray;
  const Bases: TLandrixXmlXPathIntArray; Count, Node: Integer; out Base: Integer): TLandrixXmlXPathTree;
var
  Lo, Hi, M: Integer;
begin
  Base := 0;
  Result := Main;
  if (Node < Main.Count) or (Count = 0) then
    Exit;
  { the last tree whose base is at most Node }
  Lo := 0;
  Hi := Count - 1;
  while Lo < Hi do
  begin
    M := Lo + (Hi - Lo + 1) div 2;
    if Bases[M] <= Node then
      Lo := M
    else
      Hi := M - 1;
  end;
  Base := Bases[Lo];
  Result := Trees[Lo];
end;

function TLandrixXmlXPathResult.StringValueUtf8(Index: Integer): TLandrixXmlUtf8;
var
  T: TLandrixXmlXPathTree;
  Base: Integer;
begin
  if FItems.Items[Index].Kind = xikNode then
  begin
    T := NodeTree(FTree, FDocTrees, FDocBases, FDocCount, FItems.Items[Index].Node, Base);
    Result := T.StringValueUtf8(FItems.Items[Index].Node - Base);
  end
  else
    Result := AtomicString(FItems.Items[Index]);
end;

function TLandrixXmlXPathResult.AsBoolean: Boolean;
begin
  Result := SequenceBoolean(FItems);
end;

{ --- TLandrixXmlXPathEvaluator ---------------------------------------------- }

constructor TLandrixXmlXPathEvaluator.Create(Tree: TLandrixXmlXPathTree);
begin
  inherited Create;
  FTree := Tree;
  FMaxDepth := 500;
  FImplicitTimeZone := 0;
  FHasClock := False;
  FCurrentNode := -1;
  FRegexes := TObjectList.Create(True);
  FCaches := TObjectList.Create(True);
  FKeyIndexes := TObjectList.Create(True);
  FBypass := -1;
end;

destructor TLandrixXmlXPathEvaluator.Destroy;
begin
  FKeyIndexes.Free;
  FCaches.Free;
  FRegexes.Free;
  inherited Destroy;
end;

{ --- kept values of context-free subexpressions ------------------------- }

const
  { more expressions than that in one evaluator: start again }
  MaxCachedExpressions = 4096;

const
  ContextFunctions = [xfnString, xfnStringLength, xfnNormalizeSpace, xfnNumber, xfnName, xfnLocalName,
    xfnNamespaceUri, xfnRoot, xfnNodeName, xfnBaseUri];

{ What the value of node Index depends on besides the tree and the global
  variables; Free receives the nodes that depend on nothing else but the
  root of the context's tree, Rooted those that depend on that root. }
function Dependencies(const Nodes: TLandrixXmlXPathAstNodes; Index, GlobalCount, FirstLocalSlot: Integer;
  var Free, Rooted: array of Boolean): TDependencies;
var
  I, First: Integer;
  Id: TLandrixXmlXPathFunctionId;
  Deps: TDependencies;

  { predicates and later steps have a focus (and a root) of their own }
  procedure Inner(Child: Integer);
  begin
    Deps := Deps + Dependencies(Nodes, Child, GlobalCount, FirstLocalSlot, Free, Rooted) * [xdOther];
  end;

begin
  Deps := [];
  case Nodes[Index].Kind of
    xakContextItem, xakRoot:
      Deps := [xdFocus];
    xakStep:
      begin
        Deps := [xdFocus];
        for I := 0 to Integer(High(Nodes[Index].Predicates)) do
          Inner(Nodes[Index].Predicates[I]);
      end;
    xakPath:
      begin
        First := 0;
        if not Nodes[Index].RootStart then
        begin
          Deps := Dependencies(Nodes, Nodes[Index].Children[0], GlobalCount, FirstLocalSlot, Free, Rooted);
          First := 1;
        end
        else
          { "/" needs a node as context: the root of its tree }
          Deps := [xdRoot];
        for I := First to Integer(High(Nodes[Index].Children)) do
          Inner(Nodes[Index].Children[I]);
      end;
    xakFilter:
      begin
        Deps := Dependencies(Nodes, Nodes[Index].Children[0], GlobalCount, FirstLocalSlot, Free, Rooted);
        for I := 0 to Integer(High(Nodes[Index].Predicates)) do
          Inner(Nodes[Index].Predicates[I]);
      end;
    xakVariable:
      { global: a slot of the static context below GlobalCount; the slots
        from FirstLocalSlot on are those of for, some and every }
      if (Nodes[Index].Slot >= GlobalCount) or (Nodes[Index].Slot >= FirstLocalSlot) then
        Deps := [xdOther];
  else
    for I := 0 to Integer(High(Nodes[Index].Children)) do
      Deps := Deps + Dependencies(Nodes, Nodes[Index].Children[I], GlobalCount, FirstLocalSlot, Free, Rooted);
    for I := 0 to Integer(High(Nodes[Index].Predicates)) do
      Inner(Nodes[Index].Predicates[I]);
    { a user function the caller implements may read more }
    if (Nodes[Index].Kind = xakFunction) and (Nodes[Index].Op < 0) then
    begin
      if xffFocus in Nodes[Index].FunctionFlags then
        Include(Deps, xdFocus);
      if xffVolatile in Nodes[Index].FunctionFlags then
        Include(Deps, xdOther);
    end;
    if (Nodes[Index].Kind = xakFunction) and (Nodes[Index].Op >= 0) then
    begin
      Id := TLandrixXmlXPathFunctionId(Nodes[Index].Op);
      { lang(), id() and idref() with one argument read the context node }
      if (Id = xfnPosition) or (Id = xfnLast) or ((Id in ContextFunctions) and (Length(Nodes[Index].Children) = 0)) or
        ((Id in [xfnLang, xfnId, xfnIdref]) and (Length(Nodes[Index].Children) = 1)) then
        Include(Deps, xdFocus)
      else if Id = xfnCurrent then
        Include(Deps, xdOther);
    end;
  end;
  Free[Index] := Deps - [xdRoot] = [];
  Rooted[Index] := xdRoot in Deps;
  Result := Deps;
end;

{ True if the predicate Index may depend on the position: it may be a
  number, or it calls position() or last(). }
function MayBePositional(const Nodes: TLandrixXmlXPathAstNodes; Index: Integer): Boolean;
const
  NotNumeric = [xfnNot, xfnTrue, xfnFalse, xfnBoolean, xfnExists, xfnEmpty, xfnContains, xfnStartsWith,
    xfnEndsWith, xfnMatches, xfnString, xfnNormalizeSpace, xfnConcat, xfnUpperCase, xfnLowerCase, xfnName,
    xfnLocalName];

  function UsesPosition(I: Integer): Boolean;
  var
    J: Integer;
  begin
    Result := (Nodes[I].Kind = xakFunction) and ((Nodes[I].Op >= 0) and
      (TLandrixXmlXPathFunctionId(Nodes[I].Op) in [xfnPosition, xfnLast]) or
      (Nodes[I].Op < 0) and (xffFocus in Nodes[I].FunctionFlags));
    J := 0;
    while not Result and (J < Length(Nodes[I].Children)) do
    begin
      Result := UsesPosition(Nodes[I].Children[J]);
      Inc(J);
    end;
    J := 0;
    while not Result and (J < Length(Nodes[I].Predicates)) do
    begin
      Result := UsesPosition(Nodes[I].Predicates[J]);
      Inc(J);
    end;
  end;

begin
  case Nodes[Index].Kind of
    xakGeneralCompare, xakValueCompare, xakAnd, xakOr, xakString, xakCastable, xakUnion, xakSome, xakEvery,
    xakStep, xakIntersectExcept, xakNodeCompare, xakInstanceOf:
      Result := False;
    xakTreat:
      Result := MayBePositional(Nodes, Nodes[Index].Children[0]);
    xakPath:
      Result := Nodes[Nodes[Index].Children[Integer(High(Nodes[Index].Children))]].Kind <> xakStep;
    xakFunction:
      Result := (Nodes[Index].Op < 0) or not (TLandrixXmlXPathFunctionId(Nodes[Index].Op) in NotNumeric);
  else
    Result := True;
  end;
  if not Result then
    Result := UsesPosition(Index);
end;

{ Marks the outermost free nodes that are worth keeping. }
procedure MarkOutermost(const Nodes: TLandrixXmlXPathAstNodes; Index: Integer; ParentFree: Boolean;
  const Free: array of Boolean; var Flags: array of Boolean);
var
  I: Integer;
begin
  Flags[Index] := Free[Index] and not ParentFree and not (Nodes[Index].Kind in [xakEmpty, xakString, xakInteger,
    xakDecimal, xakDouble, xakVariable]);
  for I := 0 to Integer(High(Nodes[Index].Children)) do
    MarkOutermost(Nodes, Nodes[Index].Children[I], Free[Index], Free, Flags);
  for I := 0 to Integer(High(Nodes[Index].Predicates)) do
    MarkOutermost(Nodes, Nodes[Index].Predicates[I], Free[Index], Free, Flags);
end;

{ True if Index calls a user function flagged xffVolatile (anywhere below
  it). }
function CallsVolatile(const Nodes: TLandrixXmlXPathAstNodes; Index: Integer): Boolean;
var
  J: Integer;
begin
  Result := (Nodes[Index].Kind = xakFunction) and (Nodes[Index].Op < 0) and
    (xffVolatile in Nodes[Index].FunctionFlags);
  J := 0;
  while not Result and (J < Length(Nodes[Index].Children)) do
  begin
    Result := CallsVolatile(Nodes, Nodes[Index].Children[J]);
    Inc(J);
  end;
  J := 0;
  while not Result and (J < Length(Nodes[Index].Predicates)) do
  begin
    Result := CallsVolatile(Nodes, Nodes[Index].Predicates[J]);
    Inc(J);
  end;
end;

{ A step "name[@attribute = value][...]" on the child axis whose value
  depends neither on the focus nor on the root of its tree (a string
  literal, a variable, a path from document()): Attribute and Value
  receive the attribute step and the value, otherwise -1. A number
  literal compares as a number: never indexed. }
procedure FindKey(const Nodes: TLandrixXmlXPathAstNodes; Index, GlobalCount, FirstLocalSlot: Integer;
  var Free, Rooted: array of Boolean; out Attribute, Value: Integer);
var
  P, Side, A, B: Integer;
begin
  Attribute := -1;
  Value := -1;
  if (Nodes[Index].Kind <> xakStep) or (Nodes[Index].Axis <> xaxChild) or (Nodes[Index].NodeTest <> xntName) or
    (Length(Nodes[Index].Predicates) = 0) then
    Exit;
  P := Nodes[Index].Predicates[0];
  if (Nodes[P].Kind <> xakGeneralCompare) or (TLandrixXmlXPathCompare(Nodes[P].Op) <> xpcEq) or
    (Length(Nodes[P].Children) <> 2) then
    Exit;
  for Side := 0 to 1 do
  begin
    A := Nodes[P].Children[Side];
    B := Nodes[P].Children[1 - Side];
    if (Nodes[A].Kind = xakStep) and (Nodes[A].Axis = xaxAttribute) and (Nodes[A].NodeTest = xntName) and
      (Length(Nodes[A].Predicates) = 0) and not (Nodes[B].Kind in [xakInteger, xakDecimal, xakDouble]) and
      (Dependencies(Nodes, B, GlobalCount, FirstLocalSlot, Free, Rooted) * [xdFocus, xdRoot] = []) and
      not CallsVolatile(Nodes, B) then
    begin
      Attribute := A;
      Value := B;
      Exit;
    end;
  end;
end;

function TLandrixXmlXPathEvaluator.FindCache(Expr: TLandrixXmlXPathExpression): TObject;
var
  H, Mask, I, J, Count: Integer;
  C: TExpressionCache;
  Free, KeyFree, KeyRooted: array of Boolean;
begin
  Result := nil;
  Free := nil;
  KeyFree := nil;
  KeyRooted := nil;
  if (Expr = nil) or (Expr.NodeCount = 0) then
    Exit;
  if Length(FCacheTable) = 0 then
    SetLength(FCacheTable, 64);
  Mask := Integer(Length(FCacheTable)) - 1;
  H := Integer(Expr.Serial and Mask);
  while FCacheTable[H] <> nil do
  begin
    C := TExpressionCache(FCacheTable[H]);
    if (C.Expression = Expr) and (C.Serial = Expr.Serial) then
    begin
      Result := C;
      Exit;
    end;
    H := (H + 1) and Mask;
  end;
  if FCaches.Count >= MaxCachedExpressions then
  begin
    { inside an evaluation an entry may be in use: no new one }
    if FNesting > 1 then
      Exit;
    FCaches.Clear;
    FCacheTable := nil;
    SetLength(FCacheTable, 64);
    Mask := 63;
    H := Integer(Expr.Serial and Mask);
  end;
  C := TExpressionCache.Create;
  FCaches.Add(C);
  C.Expression := Expr;
  C.Serial := Expr.Serial;
  Count := Expr.NodeCount;
  SetLength(Free, Count);
  SetLength(C.Flags, Count);
  SetLength(C.RootOnly, Count);
  SetLength(C.Have, Count);
  SetLength(C.Values, Count);
  for I := 0 to Count - 1 do
  begin
    Free[I] := False;
    C.Flags[I] := False;
    C.Have[I] := False;
    C.RootOnly[I] := False;
  end;
  Dependencies(Expr.NodeArray, Expr.Root, FGlobalCount, Expr.FirstLocalSlot, Free, C.RootOnly);
  MarkOutermost(Expr.NodeArray, Expr.Root, False, Free, C.Flags);
  SetLength(C.Fuse, Count);
  for I := 0 to Count - 1 do
  begin
    C.Fuse[I] := (Expr.NodeArray[I].Kind = xakStep) and (Expr.NodeArray[I].Axis = xaxChild);
    J := 0;
    while C.Fuse[I] and (J < Length(Expr.NodeArray[I].Predicates)) do
    begin
      C.Fuse[I] := not MayBePositional(Expr.NodeArray, Expr.NodeArray[I].Predicates[J]);
      Inc(J);
    end;
  end;
  { Free and C.Flags are set; the key search only needs scratch arrays }
  SetLength(C.KeyAttribute, Count);
  SetLength(C.KeyValue, Count);
  SetLength(KeyFree, Count);
  SetLength(KeyRooted, Count);
  for I := 0 to Count - 1 do
    FindKey(Expr.NodeArray, I, FGlobalCount, Expr.FirstLocalSlot, KeyFree, KeyRooted, C.KeyAttribute[I],
      C.KeyValue[I]);
  FCacheTable[H] := C;
  Result := C;
  { at most half full; the entries of a freed expression stay (an
    expression at the same address has another serial) }
  if 2 * FCaches.Count > Length(FCacheTable) then
  begin
    Count := 2 * Integer(Length(FCacheTable));
    FCacheTable := nil;
    SetLength(FCacheTable, Count);
    Mask := Count - 1;
    for I := 0 to Integer(FCaches.Count) - 1 do
    begin
      H := Integer(TExpressionCache(FCaches[I]).Serial and Mask);
      while FCacheTable[H] <> nil do
        H := (H + 1) and Mask;
      FCacheTable[H] := FCaches[I];
    end;
  end;
end;

procedure TLandrixXmlXPathEvaluator.DropCachedValues;
var
  I, J: Integer;
  C: TExpressionCache;
begin
  for I := 0 to Integer(FCaches.Count) - 1 do
  begin
    C := TExpressionCache(FCaches[I]);
    for J := 0 to Integer(Length(C.Have)) - 1 do
      if C.Have[J] then
      begin
        C.Have[J] := False;
        C.Values[J] := LandrixXmlXPathEmpty;
      end;
  end;
end;

procedure TLandrixXmlXPathEvaluator.ClearCache;
begin
  DropCachedValues;
  { the evaluator's tree may have another size now }
  ComputeBases;
end;

{ The kept values and the evaluated variables depend on the dynamic
  context: forget them (variables bound lazily are evaluated again). }
procedure TLandrixXmlXPathEvaluator.ResetDynamicContext;
var
  I, J: Integer;
begin
  DropCachedValues;
  for I := 0 to Integer(Length(FGlobals)) - 1 do
    if (FGlobals[I].Expression <> nil) and (FGlobals[I].State in [xssValue, xssError]) then
    begin
      FGlobals[I].State := xssLazy;
      FGlobals[I].Value := LandrixXmlXPathEmpty;
    end;
  for I := 0 to Integer(Length(FFrame)) - 1 do
    if (FFrame[I].Expression <> nil) and (FFrame[I].State in [xssValue, xssError]) then
    begin
      FFrame[I].State := xssLazy;
      FFrame[I].Value := LandrixXmlXPathEmpty;
    end;
  { and those of the frames below it (PushFrame) }
  for J := 0 to FFrameTop - 1 do
    for I := 0 to Integer(Length(FFrameStack[J])) - 1 do
      if (FFrameStack[J][I].Expression <> nil) and (FFrameStack[J][I].State in [xssValue, xssError]) then
      begin
        FFrameStack[J][I].State := xssLazy;
        FFrameStack[J][I].Value := LandrixXmlXPathEmpty;
      end;
end;

procedure TLandrixXmlXPathEvaluator.SetImplicitTimeZone(Value: Integer);
begin
  if (Value < -840) or (Value > 840) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'ImplicitTimeZone must be between -840 and 840 minutes');
  if Value = FImplicitTimeZone then
    Exit;
  FImplicitTimeZone := Value;
  ResetDynamicContext;
end;

procedure TLandrixXmlXPathEvaluator.SetCurrentDateTime(const Value: TLandrixXmlXsdDateTime);
begin
  if (Value.Year = 0) or (Value.Year = Low(Integer)) or (Value.Month < 1) or (Value.Month > 12) or
    (Value.Day < 1) or (Value.Day > DaysInMonth(Value.Year, Value.Month)) or (Value.Hour < 0) or
    (Value.Hour > 23) or (Value.Minute < 0) or (Value.Minute > 59) or (LandrixXmlDecimalSign(Value.Second) < 0) or
    (LandrixXmlDecimalCompare(Value.Second, LandrixXmlDecimalFromInt64(60)) >= 0) or
    Value.HasTimeZone and ((Value.TimeZone < -840) or (Value.TimeZone > 840)) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'CurrentDateTime: not a valid date and time');
  FClock := Value;
  FHasClock := True;
  ResetDynamicContext;
end;

procedure TLandrixXmlXPathEvaluator.ClearCurrentDateTime;
begin
  FHasClock := False;
  ResetDynamicContext;
end;

function TLandrixXmlXPathEvaluator.GetCurrentDateTime: TLandrixXmlXsdDateTime;
begin
  Result := ItemDateTime(ClockItem(xikDateTime));
end;

{ current-dateTime() and the others: the set value or the clock, in the
  implicit time zone }
function TLandrixXmlXPathEvaluator.ClockItem(Kind: TLandrixXmlXPathItemKind): TLandrixXmlXPathItem;
var
  T: TDateTime;
  Y, Mo, D, H, Mi, S, Ms: Word;
begin
  if not FHasClock then
  begin
    T := Now;
    DecodeDate(T, Y, Mo, D);
    DecodeTime(T, H, Mi, S, Ms);
    FClock.Year := Y;
    FClock.Month := Mo;
    FClock.Day := D;
    FClock.Hour := H;
    FClock.Minute := Mi;
    FClock.Second := LandrixXmlDecimalAdd(LandrixXmlDecimalFromInt64(S),
      LandrixXmlDecimalMultiplyPow10(LandrixXmlDecimalFromInt64(Ms), -3));
    FClock.HasTimeZone := False;
    FClock.TimeZone := 0;
    FHasClock := True;
  end;
  Result := AdjustToTimeZone(DateItem(xikDateTime, FClock, DateText(FClock, xikDateTime)), True, FImplicitTimeZone);
  if Kind <> xikDateTime then
    Result := CastDateKind(Result, Kind);
end;

{ Appends Tree after the trees added so far, with the next free node
  numbers. }
procedure TLandrixXmlXPathEvaluator.AppendTree(const Uri: TLandrixXmlUtf8; Tree: TLandrixXmlXPathTree;
  Named: Boolean);
var
  Next: Int64;
  N: Integer;
begin
  if (Tree = nil) or (Tree = FTree) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'XPath evaluator: another tree is needed');
  if FDocCount = 0 then
    Next := FTree.Count
  else
    Next := Int64(FDocBases[FDocCount - 1]) + FDocTrees[FDocCount - 1].Count;
  if Next + Tree.Count > MaxInt then
    raise ELandrixXmlError.CreateCode(xecLimit, 'XPath evaluator: too many nodes');
  if FDocCount = Length(FDocTrees) then
  begin
    { every tree has a node: at most MaxInt trees }
    if FDocCount > (MaxInt - 4) div 2 then
      N := MaxInt
    else
      N := 2 * FDocCount + 4;
    SetLength(FDocUris, N);
    SetLength(FDocTrees, N);
    SetLength(FDocBases, N);
    SetLength(FDocNamed, N);
  end;
  FDocUris[FDocCount] := Uri;
  FDocTrees[FDocCount] := Tree;
  FDocBases[FDocCount] := Integer(Next);
  FDocNamed[FDocCount] := Named;
  Inc(FDocCount);
end;

procedure TLandrixXmlXPathEvaluator.AddDocument(const Uri: TLandrixXmlUtf8; Tree: TLandrixXmlXPathTree);
begin
  if (Tree <> nil) and (Tree.Kind[0] <> xnkDocument) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'AddDocument: the tree has no document node');
  AppendTree(Uri, Tree, True);
  { kept values and evaluated lazy variables may have read the documents
    (doc-available, doc) }
  ResetDynamicContext;
end;

function TLandrixXmlXPathEvaluator.AddTree(Tree: TLandrixXmlXPathTree): Integer;
begin
  AppendTree('', Tree, False);
  Result := FDocBases[FDocCount - 1];
end;

{ The node numbers: the evaluator's tree, then the added trees in turn
  (again after ClearCache: the evaluator's tree may have another size). }
procedure TLandrixXmlXPathEvaluator.ComputeBases;
var
  K: Integer;
  Next: Int64;
begin
  { the node numbers change: the indexes hold them }
  DropKeyIndexes;
  Next := FTree.Count;
  for K := 0 to FDocCount - 1 do
  begin
    if Next + FDocTrees[K].Count > MaxInt then
      raise ELandrixXmlError.CreateCode(xecLimit, 'AddDocument: too many nodes');
    FDocBases[K] := Integer(Next);
    Next := Next + FDocTrees[K].Count;
  end;
end;

function TLandrixXmlXPathEvaluator.TreeOf(Node: Integer; out Base: Integer): TLandrixXmlXPathTree;
begin
  Result := NodeTree(FTree, FDocTrees, FDocBases, FDocCount, Node, Base);
end;

{ The name and type annotation of element(N, T) or attribute(N, T) on an
  untyped tree: elements are xs:untyped, attributes xs:untypedAtomic. }
function NameAndTypeMatch(Tree: TLandrixXmlXPathTree; I: Integer; const T: TLandrixXmlXPathSequenceType;
  Element: Boolean): Boolean;
begin
  Result := (T.LocalName = '') or ((Tree.LocalNameUtf8(I) = T.LocalName) and
    (Tree.NamespaceUriUtf8(I) = T.NamespaceUri));
  if Result and (T.ContentType <> '') then
    if Element then
      Result := (T.ContentType = 'anyType') or (T.ContentType = 'untyped')
    else
      Result := (T.ContentType = 'anyType') or (T.ContentType = 'anySimpleType') or
        (T.ContentType = 'anyAtomicType') or (T.ContentType = 'untypedAtomic');
end;

{ True if the node matches the kind test of T (T.Kind = xtkNode). }
function TLandrixXmlXPathEvaluator.NodeMatches(Node: Integer; const T: TLandrixXmlXPathSequenceType): Boolean;
var
  Tree: TLandrixXmlXPathTree;
  Base, I, Child, Elements: Integer;
  K: TLandrixXmlXPathNodeKind;
begin
  Tree := TreeOf(Node, Base);
  I := Node - Base;
  K := Tree.Kind[I];
  case T.KindTest of
    xktAnyNode: Result := True;
    xktElement: Result := (K = xnkElement) and NameAndTypeMatch(Tree, I, T, True);
    xktAttribute: Result := (K = xnkAttribute) and NameAndTypeMatch(Tree, I, T, False);
    xktText: Result := K = xnkText;
    xktComment: Result := K = xnkComment;
    xktProcessingInstruction:
      Result := (K = xnkProcessingInstruction) and ((T.LocalName = '') or (Tree.LocalNameUtf8(I) = T.LocalName));
  else
    begin
      Result := K = xnkDocument;
      { document-node(element(...)): exactly one element, which matches,
        besides comments and processing instructions only }
      if Result and T.ElementTest then
      begin
        Elements := 0;
        Child := Tree.FirstChild(I);
        while Child >= 0 do
        begin
          case Tree.Kind[Child] of
            xnkElement:
              begin
                Inc(Elements);
                if not NameAndTypeMatch(Tree, Child, T, True) then
                  Result := False;
              end;
            xnkText:
              Result := False;
          else
            { comments, processing instructions }
          end;
          Child := Tree.NextSibling[Child];
        end;
        Result := Result and (Elements = 1);
      end;
    end;
  end;
end;

{ The type an atomic type is derived from by restriction; xikAnyAtomic
  for the primitive types (and xs:untypedAtomic). }
function BaseKind(Kind: TLandrixXmlXPathItemKind): TLandrixXmlXPathItemKind;
begin
  case Kind of
    xikInteger: Result := xikDecimal;
    xikNonPositiveInteger, xikLong, xikNonNegativeInteger: Result := xikInteger;
    xikNegativeInteger: Result := xikNonPositiveInteger;
    xikInt: Result := xikLong;
    xikShort: Result := xikInt;
    xikByte: Result := xikShort;
    xikUnsignedLong, xikPositiveInteger: Result := xikNonNegativeInteger;
    xikUnsignedInt: Result := xikUnsignedLong;
    xikUnsignedShort: Result := xikUnsignedInt;
    xikUnsignedByte: Result := xikUnsignedShort;
    xikNormalizedString: Result := xikString;
    xikToken: Result := xikNormalizedString;
    xikLanguage, xikNMTOKEN, xikName: Result := xikToken;
    xikNCName: Result := xikName;
    xikID, xikIDREF, xikENTITY: Result := xikNCName;
    xikYearMonthDuration, xikDayTimeDuration: Result := xikDuration;
  else
    Result := xikAnyAtomic;
  end;
end;

{ True if an atomic value of Kind is an instance of the atomic type T:
  Kind is T or derived from it (no promotion, which belongs to the
  function conversion rules). }
function AtomicKindMatches(Kind, T: TLandrixXmlXPathItemKind): Boolean;
begin
  Result := True;
  while Kind <> xikAnyAtomic do
  begin
    if Kind = T then
      Exit;
    Kind := BaseKind(Kind);
  end;
  Result := T = xikAnyAtomic;
end;

{ SequenceType matching: instance of, treat as. }
function TLandrixXmlXPathEvaluator.SequenceMatches(const S: TLandrixXmlXPathSequence;
  const T: TLandrixXmlXPathSequenceType): Boolean;
var
  I: Integer;
begin
  if T.Kind = xtkEmpty then
  begin
    Result := S.Count = 0;
    Exit;
  end;
  case T.Occurrence of
    xocOne: Result := S.Count = 1;
    xocOptional: Result := S.Count <= 1;
    xocOneOrMore: Result := S.Count >= 1;
  else
    Result := True;
  end;
  I := 0;
  while Result and (I < S.Count) do
  begin
    case T.Kind of
      xtkNode: Result := (S.Items[I].Kind = xikNode) and NodeMatches(S.Items[I].Node, T);
      xtkAtomic: Result := (S.Items[I].Kind <> xikNode) and AtomicKindMatches(S.Items[I].Kind, T.AtomicType);
    else
      { item() }
    end;
    Inc(I);
  end;
end;

{ the root of Node's tree: its document node, or the node at the top of a
  tree built without one }
function TLandrixXmlXPathEvaluator.RootOf(Node: Integer): Integer;
begin
  TreeOf(Node, Result);
end;

function TLandrixXmlXPathEvaluator.DocumentRootOf(Node: Integer): Integer;
begin
  if TreeOf(Node, Result).Kind[0] <> xnkDocument then
    Fail('XPDY0050', 'the root of the context node is not a document node ("/")');
end;

function TLandrixXmlXPathEvaluator.CachedEval(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  C: TExpressionCache;
begin
  C := TExpressionCache(FCache);
  FBypass := Index;
  { the kept value of a rooted path is that of the evaluator's tree }
  if C.RootOnly[Index] and (Context >= FTree.Count) then
  begin
    Result := Eval(Index, Context, Position, Size, ContextItem);
    Exit;
  end;
  if C.Have[Index] then
  begin
    FBypass := -1;
    Result := C.Values[Index];
    Exit;
  end;
  Result := Eval(Index, Context, Position, Size, ContextItem);
  { no spare capacity: whoever appends to the value gets a copy }
  if Length(Result.Items) > Result.Count then
    SetLength(Result.Items, Result.Count);
  C.Values[Index] := Result;
  C.Have[Index] := True;
end;

procedure ClearSlot(var Slot: TLandrixXmlXPathSlot);
begin
  Slot.State := xssUnbound;
  Slot.Value := LandrixXmlXPathEmpty;
  Slot.Expression := nil;
  Slot.ContextNode := -1;
  Slot.ErrorCode := '';
  Slot.ErrorMessage := '';
  Slot.ErrorRaised := False;
  Slot.DeclaredType.Declared := False;
end;

procedure TLandrixXmlXPathEvaluator.SetGlobalCount(Count: Integer);
var
  I: Integer;
begin
  { what is context-free depends on which slots are global }
  FGlobalCount := Count;
  FCaches.Clear;
  FCacheTable := nil;
  FCache := FindCache(FExpr);
  SetLength(FGlobals, Count);
  for I := 0 to Count - 1 do
    ClearSlot(FGlobals[I]);
end;

procedure TLandrixXmlXPathEvaluator.SetFrameSize(Size: Integer);
var
  I: Integer;
begin
  SetLength(FFrame, Size);
  for I := 0 to Size - 1 do
    ClearSlot(FFrame[I]);
end;

procedure TLandrixXmlXPathEvaluator.PushFrame(Size: Integer);
var
  I: Integer;
  Frame: TLandrixXmlXPathSlots;
begin
  if Size < 0 then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'PushFrame: negative size');
  { everything that may fail first: the current frame stays if it does }
  if FFrameTop = Length(FFrameStack) then
    SetLength(FFrameStack, 2 * FFrameTop + 8);
  Frame := nil;
  SetLength(Frame, Size);
  for I := 0 to Size - 1 do
    ClearSlot(Frame[I]);
  { the old frame stays alive on the stack (a slot being read keeps a
    pointer into it) }
  FFrameStack[FFrameTop] := FFrame;
  Inc(FFrameTop);
  FFrame := Frame;
end;

procedure TLandrixXmlXPathEvaluator.PopFrame;
begin
  if FFrameTop = 0 then
    raise ELandrixXmlError.CreateCode(xecInvalidOperation, 'PopFrame: no frame was pushed');
  Dec(FFrameTop);
  FFrame := FFrameStack[FFrameTop];
  FFrameStack[FFrameTop] := nil;
end;

procedure TLandrixXmlXPathEvaluator.UnbindFrame;
var
  I: Integer;
begin
  for I := 0 to Integer(Length(FFrame)) - 1 do
    ClearSlot(FFrame[I]);
end;

function TLandrixXmlXPathEvaluator.SlotRef(Slot: Integer): Pointer;
begin
  if Slot < FGlobalCount then
    Result := @FGlobals[Slot]
  else
  begin
    if Slot >= Length(FFrame) then
      Fail('XPDY0002', 'variable slot ' + IntToStr(Slot) + ' is not bound');
    Result := @FFrame[Slot];
  end;
end;

procedure TLandrixXmlXPathEvaluator.BindValue(Slot: Integer; const Value: TLandrixXmlXPathSequence);
var
  P: PSlot;
begin
  P := SlotRef(Slot);
  ClearSlot(P^);
  P^.State := xssValue;
  P^.Value := Value;
  if Slot < FGlobalCount then
    DropCachedValues;
end;

procedure TLandrixXmlXPathEvaluator.BindString(Slot: Integer; const Value: TLandrixXmlUtf8);
begin
  BindValue(Slot, LandrixXmlXPathStringItem(Value));
end;

procedure TLandrixXmlXPathEvaluator.BindLazy(Slot: Integer; Expr: TLandrixXmlXPathExpression; ContextNode: Integer);
var
  P: PSlot;
begin
  P := SlotRef(Slot);
  ClearSlot(P^);
  P^.State := xssLazy;
  P^.Expression := Expr;
  P^.ContextNode := ContextNode;
  if Slot < FGlobalCount then
    DropCachedValues;
end;

procedure TLandrixXmlXPathEvaluator.BindLazyAs(Slot: Integer; Expr: TLandrixXmlXPathExpression;
  ContextNode: Integer; const T: TLandrixXmlXPathSequenceType);
begin
  BindLazy(Slot, Expr, ContextNode);
  PSlot(SlotRef(Slot))^.DeclaredType := T;
end;

procedure TLandrixXmlXPathEvaluator.EnterExpression(Expr: TLandrixXmlXPathExpression;
  out SavedExpr: TLandrixXmlXPathExpression; out SavedBase: Integer);
var
  Need, I: Integer;
begin
  SavedExpr := FExpr;
  SavedBase := FLocalBase;
  FExpr := Expr;
  FNodes := Expr.NodeArray;
  Inc(FNesting);
  FCache := FindCache(Expr);
  FLocalBase := FLocalTop;
  Need := Expr.SlotCount - Expr.FirstLocalSlot;
  if Need > 0 then
  begin
    if FLocalTop + Need > Length(FLocals) then
      SetLength(FLocals, 2 * (FLocalTop + Need) + 8);
    for I := FLocalTop to FLocalTop + Need - 1 do
      FLocals[I] := LandrixXmlXPathEmpty;
    Inc(FLocalTop, Need);
  end;
end;

procedure TLandrixXmlXPathEvaluator.LeaveExpression(SavedExpr: TLandrixXmlXPathExpression; SavedBase: Integer);
begin
  FLocalTop := FLocalBase;
  Dec(FNesting);
  FExpr := SavedExpr;
  FLocalBase := SavedBase;
  if FExpr <> nil then
    FNodes := FExpr.NodeArray
  else
    FNodes := nil;
  FCache := FindCache(FExpr);
end;

function TLandrixXmlXPathEvaluator.ReadVariable(Slot: Integer): TLandrixXmlXPathSequence;
var
  P: PSlot;
  SavedExpr: TLandrixXmlXPathExpression;
  SavedBase, Node, SavedCurrent: Integer;
  Value: TLandrixXmlXPathSequence;
  Empty: TLandrixXmlXPathSequence;
  SavedPattern, SavedFinal: Boolean;
begin
  if Slot >= FExpr.FirstLocalSlot then
  begin
    Result := FLocals[FLocalBase + Slot - FExpr.FirstLocalSlot];
    Exit;
  end;
  P := SlotRef(Slot);
  case P^.State of
    xssValue:
      Result := P^.Value;
    xssLazy:
      begin
        P^.State := xssEvaluating;
        Node := P^.ContextNode;
        Empty := LandrixXmlXPathEmpty;
        { current() is the variable's own context item (the document for
          a global, the rule's node for a rule variable, none for -1) }
        SavedCurrent := FCurrentNode;
        FCurrentNode := Node;
        { a variable read in a pattern still has its value as an expression }
        SavedPattern := FPattern;
        SavedFinal := FFinal;
        FPattern := False;
        EnterExpression(P^.Expression, SavedExpr, SavedBase);
        try
          try
            if Node >= 0 then
              Value := Eval(FExpr.Root, Node, 1, 1, Empty)
            else
              Value := Eval(FExpr.Root, -1, 0, 0, Empty);
          finally
            LeaveExpression(SavedExpr, SavedBase);
            FCurrentNode := SavedCurrent;
            FPattern := SavedPattern;
            FFinal := SavedFinal;
          end;
        except
          on E: ELandrixXmlXPathError do
          begin
            { the slot may have moved if the frame grew: look it up again }
            P := SlotRef(Slot);
            P^.State := xssError;
            P^.ErrorCode := E.XPathCode;
            P^.ErrorMessage := E.Message;
            P^.ErrorRaised := E is ELandrixXmlXPathRaised;
            raise;
          end;
          on Exception do
          begin
            { not an XPath error: evaluate again next time }
            P := SlotRef(Slot);
            P^.State := xssLazy;
            raise;
          end;
        end;
        P := SlotRef(Slot);
        if P^.DeclaredType.Declared then
        begin
          try
            Value := ConvertTo(Value, P^.DeclaredType, 'variable', (P^.Expression = nil) or
              (P^.Expression.Profile = xppXPath20));
          except
            on E: ELandrixXmlXPathError do
            begin
              P := SlotRef(Slot);
              P^.State := xssError;
              P^.ErrorCode := E.XPathCode;
              P^.ErrorMessage := E.Message;
              P^.ErrorRaised := E is ELandrixXmlXPathRaised;
              raise;
            end;
          end;
          P := SlotRef(Slot);
        end;
        P^.State := xssValue;
        P^.Value := Value;
        Result := Value;
      end;
    xssEvaluating:
      begin
        Fail('XTDE0640', 'circular definition of variable slot ' + IntToStr(Slot));
        Result := LandrixXmlXPathEmpty;
      end;
    xssError:
      begin
        if P^.ErrorRaised then
          raise ELandrixXmlXPathRaised.CreateXPath(P^.ErrorCode, Copy(P^.ErrorMessage, Length(P^.ErrorCode) + 3,
            MaxInt))
        else
          raise ELandrixXmlXPathError.CreateXPath(P^.ErrorCode, Copy(P^.ErrorMessage, Length(P^.ErrorCode) + 3,
            MaxInt));
      end;
  else
    Fail('XPDY0002', 'variable slot ' + IntToStr(Slot) + ' is not bound');
    Result := LandrixXmlXPathEmpty;
  end;
end;

procedure TLandrixXmlXPathEvaluator.WriteLocal(Slot: Integer; const Value: TLandrixXmlXPathSequence);
begin
  FLocals[FLocalBase + Slot - FExpr.FirstLocalSlot] := Value;
end;

function TLandrixXmlXPathEvaluator.Xp20: Boolean;
begin
  Result := (FExpr = nil) or (FExpr.Profile = xppXPath20);
end;

function TLandrixXmlXPathEvaluator.StringOf(const Item: TLandrixXmlXPathItem): TLandrixXmlUtf8;
var
  T: TLandrixXmlXPathTree;
  Base: Integer;
begin
  if Item.Kind = xikNode then
  begin
    T := TreeOf(Item.Node, Base);
    Result := T.StringValueUtf8(Item.Node - Base);
  end
  else
    Result := AtomicString(Item);
end;

{ fn:data: nodes become their typed value (untypedAtomic, xs:string for
  comments and processing instructions). }
function TLandrixXmlXPathEvaluator.Atomize(const S: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  I, Base: Integer;
  HasNode: Boolean;
  T: TLandrixXmlXPathTree;
begin
  HasNode := False;
  for I := 0 to S.Count - 1 do
    if S.Items[I].Kind = xikNode then
    begin
      HasNode := True;
      Break;
    end;
  if not HasNode then
  begin
    Result := S;
    Exit;
  end;
  Result := LandrixXmlXPathEmpty;
  SetLength(Result.Items, S.Count);
  for I := 0 to S.Count - 1 do
    if S.Items[I].Kind = xikNode then
    begin
      T := TreeOf(S.Items[I].Node, Base);
      if T.Kind[S.Items[I].Node - Base] in [xnkComment, xnkProcessingInstruction] then
        LandrixXmlXPathAppend(Result, StringItem(xikString, T.StringValueUtf8(S.Items[I].Node - Base)))
      else
        LandrixXmlXPathAppend(Result, StringItem(xikUntypedAtomic, T.StringValueUtf8(S.Items[I].Node - Base)));
    end
    else
      LandrixXmlXPathAppend(Result, S.Items[I]);
end;

function TLandrixXmlXPathEvaluator.Regex(const Pattern, Flags: TLandrixXmlUtf8): TLandrixXmlRegex;
var
  Key: TLandrixXmlUtf8;
  I: Integer;
  Mode: TLandrixXmlRegexMode;
begin
  { the dialect of the profile: XML Schema 1.0 character classes in XPath 2.0 }
  if Xp20 then
  begin
    Mode := xrmXPath20;
    Key := '2' + Flags + #0 + Pattern;
  end
  else
  begin
    Mode := xrmXPath;
    Key := '3' + Flags + #0 + Pattern;
  end;
  for I := Integer(FRegexes.Count) - 1 downto 0 do
    if FRegexKeys[I] = Key then
    begin
      Result := TLandrixXmlRegex(FRegexes[I]);
      Exit;
    end;
  if not LandrixXmlRegexFlagsValid(Flags, Mode) then
    Fail('FORX0001', 'invalid regular expression flags ''' + LandrixXmlEscapeForMessage(Flags, 20) + '''');
  try
    Result := TLandrixXmlRegex.Create(Pattern, Mode, Flags);
  except
    on E: ELandrixXmlError do
    begin
      { a limit of this implementation is no invalid pattern }
      if E.Code = xecUnsupported then
        Fail('FOER0000', 'unsupported regular expression: ' + E.Message);
      if E.Code = xecLimit then
        Fail('FOER0000', 'regular expression beyond the limits: ' + E.Message);
      Fail('FORX0002', 'invalid regular expression: ' + E.Message);
      Result := nil;
      Exit;
    end;
  end;
  if FRegexes.Count = Length(FRegexKeys) then
    SetLength(FRegexKeys, 2 * Integer(FRegexes.Count) + 8);
  FRegexKeys[FRegexes.Count] := Key;
  FRegexes.Add(Result);
end;

{ --- evaluation ---------------------------------------------------------------- }

function TLandrixXmlXPathEvaluator.EvaluateSequence(Expr: TLandrixXmlXPathExpression;
  ContextNode: Integer): TLandrixXmlXPathSequence;
begin
  Result := EvaluateShared(Expr, ContextNode);
  { the caller's own copy of the items (they may be kept values or a
    variable's); payloads never change and are shared }
  Result.Items := Copy(Result.Items, 0, Result.Count);
end;

function TLandrixXmlXPathEvaluator.EvaluatePattern(Expr: TLandrixXmlXPathExpression;
  ContextNode: Integer): TLandrixXmlXPathSequence;
begin
  FPattern := True;
  FFinal := True;
  FFailedCount := 0;
  FMinFailed := MaxInt;
  try
    Result := EvaluateSequence(Expr, ContextNode);
  finally
    FPattern := False;
    FFinal := False;
    FFailedCount := 0;
  end;
end;

function TLandrixXmlXPathEvaluator.ItemString(const Item: TLandrixXmlXPathItem): TLandrixXmlUtf8;
begin
  Result := StringOf(Item);
end;

function TLandrixXmlXPathEvaluator.EffectiveBoolean(const S: TLandrixXmlXPathSequence): Boolean;
begin
  Result := SequenceBoolean(S);
end;

function TLandrixXmlXPathEvaluator.ConvertSequence(const S: TLandrixXmlXPathSequence;
  const T: TLandrixXmlXPathSequenceType; const Name: string): TLandrixXmlXPathSequence;
begin
  Result := ConvertTo(S, T, Name, False);
end;

function TLandrixXmlXPathEvaluator.TreeOfNode(Node: Integer; out Base: Integer): TLandrixXmlXPathTree;
begin
  Result := TreeOf(Node, Base);
end;

function PatternMismatch(E: ELandrixXmlError): Boolean; forward;

function TLandrixXmlXPathEvaluator.MatchesPattern(Expr: TLandrixXmlXPathExpression; Node: Integer;
  Relative: Boolean): Boolean;
var
  SavedExpr: TLandrixXmlXPathExpression;
  SavedBase, PathIndex, I: Integer;
  Slow: Boolean;
  S: TLandrixXmlXPathSequence;

  function ParentOf(X: Integer): Integer;
  var
    T: TLandrixXmlXPathTree;
    B: Integer;
  begin
    T := TreeOf(X, B);
    Result := T.Parent[X - B];
    if Result >= 0 then
      Inc(Result, B);
  end;

  function KindOf(X: Integer): TLandrixXmlXPathNodeKind;
  var
    B: Integer;
  begin
    Result := TreeOf(X, B).Kind[X - B];
  end;

  function Contains(const Seq: TLandrixXmlXPathSequence; X: Integer): Boolean;
  var
    I: Integer;
  begin
    Result := True;
    for I := 0 to Seq.Count - 1 do
      if Seq.Items[I].Node = X then
        Exit;
    Result := False;
  end;

  function Positional(Step: Integer): Boolean;
  var
    I: Integer;
  begin
    Result := False;
    for I := 0 to Integer(High(FNodes[Step].Predicates)) do
      if MayBePositional(FNodes, FNodes[Step].Predicates[I]) then
        Result := True;
  end;

  { The node test of Step (child or attribute axis) on X, then its
    predicates on X alone (position 1 of 1); a dynamic error in them: no
    match (XSLT 3.0, 5.5.4, as EvaluatePattern keeps the other nodes). }
  function Alone(Step, X: Integer): Boolean;
  var
    T: TLandrixXmlXPathTree;
    B, I, Expanded: Integer;
    K: TLandrixXmlXPathNodeKind;
    N: ^TLandrixXmlXPathAstNode;
    One: TLandrixXmlXPathSequence;
  begin
    N := @FNodes[Step];
    T := TreeOf(X, B);
    I := X - B;
    K := T.Kind[I];
    case N^.NodeTest of
      xntAnyNode: Result := True;
      xntText: Result := K = xnkText;
      xntComment: Result := K = xnkComment;
      xntProcessingInstruction:
        Result := (K = xnkProcessingInstruction) and ((N^.LocalName = '') or (T.LocalNameUtf8(I) = N^.LocalName));
      xntDocumentNode: Result := K = xnkDocument;
      xntAnyElement: Result := K = xnkElement;
      xntAnyAttribute: Result := K = xnkAttribute;
      xntKindTest: Result := NodeMatches(X, N^.SequenceType);
    else
      { name tests: the principal node kind of the axis }
      if N^.Axis = xaxAttribute then
        Result := K = xnkAttribute
      else
        Result := K = xnkElement;
      if Result then
        case N^.NodeTest of
          xntName:
            begin
              Expanded := T.FindExpandedName(N^.NamespaceUri, N^.LocalName);
              Result := (Expanded >= 0) and (T.ExpandedName[I] = Expanded);
            end;
          xntNamespaceWildcard: Result := T.NamespaceUriUtf8(I) = N^.NamespaceUri;
          xntLocalWildcard: Result := T.LocalNameUtf8(I) = N^.LocalName;
        else
          { * }
        end;
    end;
    if not Result or (Length(N^.Predicates) = 0) then
      Exit;
    One := LandrixXmlXPathNodeItem(X);
    try
      Result := ApplyPredicates(N^.Predicates, One, MaxInt).Count = 1;
    except
      { limits and circular variables stay errors, as in EvaluatePattern }
      on E: ELandrixXmlError do
        if PatternMismatch(E) then
          Result := False
        else
          raise;
    end;
  end;

  { Does X belong to the nodes of the steps 0 to K (X = -1: no node, the
    context of a top node's step)? }
  function Match(K, X: Integer): Boolean;
  var
    Step, P, A: Integer;
    Ok: Boolean;
  begin
    Result := False;
    if K < 0 then
    begin
      { before the first step: "/" }
      Result := (X >= 0) and (RootOf(X) = X) and (KindOf(X) = xnkDocument);
      Exit;
    end;
    Step := FNodes[PathIndex].Children[K];
    if (FNodes[Step].Axis = xaxDescendantOrSelf) and (FNodes[Step].NodeTest = xntAnyNode) and
      (Length(FNodes[Step].Predicates) = 0) then
    begin
      { never an attribute (the context of a later step is a parent) }
      if (X >= 0) and (KindOf(X) = xnkAttribute) then
        Exit;
      { "//": the leading one of a relative pattern takes any context }
      if Relative and (K = 0) then
      begin
        Result := True;
        Exit;
      end;
      A := X;
      while A >= 0 do
      begin
        if Match(K - 1, A) then
        begin
          Result := True;
          Exit;
        end;
        A := ParentOf(A);
      end;
      Exit;
    end;
    if X < 0 then
      Exit;
    P := ParentOf(X);
    case FNodes[Step].Axis of
      xaxChild:
        if KindOf(X) in [xnkAttribute, xnkDocument] then
          Exit;
      xaxAttribute:
        if KindOf(X) <> xnkAttribute then
          Exit;
    else
      Slow := True;
      Exit;
    end;
    if P < 0 then
    begin
      { a node without parent: the first step of a relative pattern
        (XSLT 3.0: child-or-top, attribute-or-top), the node alone as the
        step's sequence }
      if Relative and (K = 1) then
        Result := Alone(Step, X);
      Exit;
    end;
    { a predicate that may read the position needs the siblings (an error
      there: EvaluatePattern decides) }
    if Positional(Step) then
      Ok := Contains(EvalStep(Step, P, FNodes[Step].Axis), X)
    else
      Ok := Alone(Step, X);
    Result := Ok and Match(K - 1, P);
  end;

  { the steps Match understands }
  function Simple(Path: Integer): Boolean;
  var
    I, Step: Integer;
  begin
    Result := (FNodes[Path].Kind = xakPath) and FNodes[Path].RootStart and (Length(FNodes[Path].Children) > 0);
    I := 0;
    while Result and (I < Length(FNodes[Path].Children)) do
    begin
      Step := FNodes[Path].Children[I];
      Result := (FNodes[Step].Kind = xakStep) and ((FNodes[Step].Axis in [xaxChild, xaxAttribute]) or
        (FNodes[Step].Axis = xaxDescendantOrSelf) and (FNodes[Step].NodeTest = xntAnyNode) and
        (Length(FNodes[Step].Predicates) = 0));
      Inc(I);
    end;
  end;

begin
  Result := False;
  if Node < 0 then
    Exit;
  Slow := False;
  EnterExpression(Expr, SavedExpr, SavedBase);
  try
    PathIndex := Expr.Root;
    if not Simple(PathIndex) then
      Slow := True
    else
      try
        Result := Match(Integer(High(FNodes[PathIndex].Children)), Node);
      except
        { a dynamic error: EvaluatePattern knows which nodes still match
          (limits and circular variables stay errors) }
        on E: ELandrixXmlError do
          if PatternMismatch(E) then
            Slow := True
          else
            raise;
      end;
  finally
    LeaveExpression(SavedExpr, SavedBase);
  end;
  if not Slow then
    Exit;
  Result := False;
  try
    S := EvaluatePattern(Expr, RootOf(Node));
  except
    { a tree without document node: "/" has no root to start from }
    on E: ELandrixXmlXPathError do
      if E.XPathCode = 'XPDY0050' then
        Exit
      else
        raise;
  end;
  { not always in document order (a variable's nodes) }
  for I := 0 to S.Count - 1 do
    if (S.Items[I].Kind = xikNode) and (S.Items[I].Node = Node) then
    begin
      Result := True;
      Exit;
    end;
end;

procedure TLandrixXmlXPathEvaluator.AddFailed(Node: Integer);
begin
  if FFailedCount = Length(FFailed) then
    SetLength(FFailed, 2 * FFailedCount + 16);
  FFailed[FFailedCount] := Node;
  Inc(FFailedCount);
end;

{ S without the nodes FFailed[First .. Last - 1] }
function TLandrixXmlXPathEvaluator.WithoutFailed(const S: TLandrixXmlXPathSequence;
  First, Last: Integer): TLandrixXmlXPathSequence;
var
  Failed: array of Boolean;
  I: Integer;
begin
  Failed := nil;
  SetLength(Failed, FTree.Count);
  for I := First to Last - 1 do
    if FFailed[I] < FTree.Count then
      Failed[FFailed[I]] := True;
  Result := LandrixXmlXPathEmpty;
  for I := 0 to S.Count - 1 do
    if (S.Items[I].Node >= FTree.Count) or not Failed[S.Items[I].Node] then
      LandrixXmlXPathAppend(Result, S.Items[I]);
end;

function TLandrixXmlXPathEvaluator.EvaluateShared(Expr: TLandrixXmlXPathExpression;
  ContextNode: Integer): TLandrixXmlXPathSequence;
var
  Empty: TLandrixXmlXPathSequence;
begin
  Empty := LandrixXmlXPathEmpty;
  if ContextNode >= 0 then
    Result := EvaluateFocusShared(Expr, ContextNode, 1, 1, Empty)
  else
    Result := EvaluateFocusShared(Expr, -1, 0, 0, Empty);
end;

function TLandrixXmlXPathEvaluator.EvaluateInFocus(Expr: TLandrixXmlXPathExpression;
  const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
var
  Has: Boolean;
  NodeLimit: Int64;
begin
  { the first number after all trees' nodes }
  if FDocCount = 0 then
    NodeLimit := FTree.Count
  else
    NodeLimit := Int64(FDocBases[FDocCount - 1]) + FDocTrees[FDocCount - 1].Count;
  Has := (Focus.Node >= 0) or (Focus.Item.Count > 0);
  if (Focus.Node < -1) or (Focus.Item.Count < 0) or (Focus.Item.Count > Length(Focus.Item.Items)) or
    (Focus.Item.Count = 1) and (Focus.Item.Items[0].Kind in [xikNone, xikAnyAtomic]) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'EvaluateInFocus: not a valid focus');
  if (Focus.Item.Count > 1) or (Focus.Node >= 0) and (Focus.Item.Count > 0) or
    (Focus.Item.Count = 1) and (Focus.Item.Items[0].Kind = xikNode) or
    Has and ((Focus.Position < 1) or (Focus.Position > Focus.Size)) or
    not Has and ((Focus.Position <> 0) or (Focus.Size <> 0)) or (Focus.Node >= NodeLimit) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'EvaluateInFocus: not a valid focus');
  Result := EvaluateFocusShared(Expr, Focus.Node, Focus.Position, Focus.Size, Focus.Item);
  Result.Items := Copy(Result.Items, 0, Result.Count);
end;

function TLandrixXmlXPathEvaluator.EvaluateFocusShared(Expr: TLandrixXmlXPathExpression;
  Context, Position, Size: Integer; const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  SavedExpr: TLandrixXmlXPathExpression;
  SavedBase: Integer;
begin
  EnterExpression(Expr, SavedExpr, SavedBase);
  try
    try
      Result := Eval(Expr.Root, Context, Position, Size, ContextItem);
    except
      { errors of the number and string units become XPath errors }
      on E: ELandrixXmlXPathError do
        raise;
      on E: ELandrixXmlError do
        case E.Code of
          xecArithmetic: Fail('FOAR0002', E.Message);
          xecConversion: Fail('FOCA0002', E.Message);
          xecRegex: Fail('FORX0002', E.Message);
        else
          Fail('FOER0000', E.Message);
        end;
    end;
  finally
    LeaveExpression(SavedExpr, SavedBase);
  end;
end;

function TLandrixXmlXPathEvaluator.Evaluate(Expr: TLandrixXmlXPathExpression;
  ContextNode: Integer): TLandrixXmlXPathResult;
begin
  Result := TLandrixXmlXPathResult.Create;
  try
    Result.FTree := FTree;
    { shared, not copied: trees added later only fill entries after
      FDocCount (or go into new arrays when the evaluator's grow) }
    Result.FDocTrees := FDocTrees;
    Result.FDocBases := FDocBases;
    Result.FDocCount := FDocCount;
    Result.FItems := EvaluateSequence(Expr, ContextNode);
  except
    Result.Free;
    raise;
  end;
end;

function TLandrixXmlXPathEvaluator.EvaluateBoolean(Expr: TLandrixXmlXPathExpression; ContextNode: Integer): Boolean;
begin
  Result := SequenceBoolean(EvaluateShared(Expr, ContextNode));
end;

function TLandrixXmlXPathEvaluator.EvaluateString(Expr: TLandrixXmlXPathExpression;
  ContextNode: Integer): TLandrixXmlUtf8;
var
  S: TLandrixXmlXPathSequence;
  I: Integer;
begin
  S := EvaluateShared(Expr, ContextNode);
  Result := '';
  for I := 0 to S.Count - 1 do
  begin
    if I > 0 then
      Result := Result + ' ';
    Result := Result + StringOf(S.Items[I]);
  end;
end;

{ Node identity and document order: merges, sorts, removes duplicates. }
procedure SortNodes(var S: TLandrixXmlXPathSequence);
var
  I, J, N: Integer;
  T: TLandrixXmlXPathItem;
  Sorted: Boolean;
begin
  Sorted := True;
  for I := 1 to S.Count - 1 do
    if S.Items[I].Node <= S.Items[I - 1].Node then
    begin
      Sorted := False;
      Break;
    end;
  if Sorted then
    Exit;
  { shell sort on the node index }
  N := 1;
  while N < S.Count div 3 do
    N := 3 * N + 1;
  while N >= 1 do
  begin
    for I := N to S.Count - 1 do
    begin
      T := S.Items[I];
      J := I;
      while (J >= N) and (S.Items[J - N].Node > T.Node) do
      begin
        S.Items[J] := S.Items[J - N];
        Dec(J, N);
      end;
      S.Items[J] := T;
    end;
    N := N div 3;
  end;
  J := 0;
  for I := 0 to S.Count - 1 do
    if (J = 0) or (S.Items[I].Node <> S.Items[J - 1].Node) then
    begin
      S.Items[J] := S.Items[I];
      Inc(J);
    end;
  S.Count := J;
end;

{ An error in a pattern's predicate that means "no match": a dynamic
  error of the rules, fn:error included. Not what this implementation
  does not support (FOER0000, XPST0017, xecUnsupported and the like) and
  not a circular variable (XTDE0640): these are raised. }
function PatternMismatch(E: ELandrixXmlError): Boolean;
var
  Code: string;
begin
  if E is ELandrixXmlXPathRaised then
    Result := True
  else if E is ELandrixXmlXPathError then
  begin
    Code := ELandrixXmlXPathError(E).XPathCode;
    Result := (Code <> 'XTDE0640') and (Code <> 'FOER0000') and (Code <> 'XPST0017');
  end
  else
    Result := E.Code in [xecArithmetic, xecConversion, xecRegex];
end;

{ True if the value of Index may be a number (a predicate then compares
  it with the position); only for the predicates of a pattern. }
function MayBeNumeric(const Nodes: TLandrixXmlXPathAstNodes; Index: Integer): Boolean;
const
  Numeric = [xfnCount, xfnSum, xfnAvg, xfnMin, xfnMax, xfnStringLength, xfnNumber, xfnAbs, xfnRound,
    xfnRoundHalfToEven, xfnFloor, xfnCeiling, xfnPosition, xfnLast, xfnIndexOf, xfnStringToCodepoints,
    xfnCompare, xfnXsDecimal, xfnXsInteger, xfnXsDouble, xfnXsFloat, xfnXsNonPositiveInteger .. xfnXsPositiveInteger];
  { the items of the first argument (distinct-values and data atomize
    them: untyped values, numbers only if the argument has numbers) }
  PassOn = [xfnReverse, xfnDistinctValues, xfnSubsequence, xfnData, xfnExactlyOne, xfnZeroOrOne,
    xfnOneOrMore, xfnRemove, xfnUnordered, xfnTrace];
var
  J: Integer;
begin
  case Nodes[Index].Kind of
    { "." too: a pattern's predicates are evaluated on nodes }
    xakGeneralCompare, xakValueCompare, xakAnd, xakOr, xakString, xakCastable, xakUnion, xakSome, xakEvery,
    xakStep, xakEmpty, xakRoot, xakContextItem, xakIntersectExcept, xakNodeCompare, xakInstanceOf:
      Result := False;
    xakTreat:
      Result := MayBeNumeric(Nodes, Nodes[Index].Children[0]);
    xakPath:
      Result := Nodes[Nodes[Index].Children[Integer(High(Nodes[Index].Children))]].Kind <> xakStep;
    xakIf:
      Result := MayBeNumeric(Nodes, Nodes[Index].Children[1]) or MayBeNumeric(Nodes, Nodes[Index].Children[2]);
    xakLet:
      Result := MayBeNumeric(Nodes, Nodes[Index].Children[1]);
    { a filter keeps items of its input }
    xakFilter:
      Result := MayBeNumeric(Nodes, Nodes[Index].Children[0]);
    xakSequence:
      begin
        Result := False;
        for J := 0 to Integer(High(Nodes[Index].Children)) do
          if MayBeNumeric(Nodes, Nodes[Index].Children[J]) then
            Result := True;
      end;
    xakCast:
      Result := Nodes[Index].AtomicType in IntegerKinds + [xikAnyAtomic, xikDecimal, xikDouble, xikFloat];
    xakFunction:
      if Nodes[Index].Op < 0 then
        Result := True
      else if TLandrixXmlXPathFunctionId(Nodes[Index].Op) in PassOn then
        Result := (Length(Nodes[Index].Children) = 0) or MayBeNumeric(Nodes, Nodes[Index].Children[0])
      { insert-before: the items of the first and the third argument }
      else if TLandrixXmlXPathFunctionId(Nodes[Index].Op) = xfnInsertBefore then
        Result := (Length(Nodes[Index].Children) < 3) or MayBeNumeric(Nodes, Nodes[Index].Children[0]) or
          MayBeNumeric(Nodes, Nodes[Index].Children[2])
      else
        Result := TLandrixXmlXPathFunctionId(Nodes[Index].Op) in Numeric;
  else
    { numbers, arithmetic, ranges, for, variables and user functions (of
      unknown type): possibly numeric, as Saxon treats them }
    Result := True;
  end;
end;

{ True if Index calls position() or last() of its own focus: not inside
  a predicate or a later step of a path, where the focus is another. }
function UsesOwnPosition(const Nodes: TLandrixXmlXPathAstNodes; Index: Integer): Boolean;
var
  J: Integer;
begin
  Result := (Nodes[Index].Kind = xakFunction) and ((Nodes[Index].Op >= 0) and
    (TLandrixXmlXPathFunctionId(Nodes[Index].Op) in [xfnPosition, xfnLast]) or
    (Nodes[Index].Op < 0) and (xffFocus in Nodes[Index].FunctionFlags));
  if Result then
    Exit;
  if Nodes[Index].Kind = xakPath then
  begin
    if not Nodes[Index].RootStart then
      Result := UsesOwnPosition(Nodes, Nodes[Index].Children[0]);
    Exit;
  end;
  J := 0;
  while not Result and (J < Length(Nodes[Index].Children)) do
  begin
    Result := UsesOwnPosition(Nodes, Nodes[Index].Children[J]);
    Inc(J);
  end;
end;

{ a predicate's value: a number is a position }
function PredicateTrue(const V: TLandrixXmlXPathSequence; Pos: Integer): Boolean;
begin
  if (V.Count = 1) and IsNumeric(V.Items[0].Kind) then
    Result := NumericEqualsInteger(V.Items[0], Pos)
  else
    Result := SequenceBoolean(V);
end;

{ The position a predicate asks for as an integer literal ([2]); 0 if
  it is none. }
function LiteralPosition(const Nodes: TLandrixXmlXPathAstNodes; Index: Integer): Int64;
begin
  { treat as keeps the value (or raises XPDY0050) }
  while Nodes[Index].Kind = xakTreat do
    Index := Nodes[Index].Children[0];
  { xs:integer(1) too }
  if (Nodes[Index].Kind = xakFunction) and (Nodes[Index].Op >= 0) and
    (TLandrixXmlXPathFunctionId(Nodes[Index].Op) = xfnXsInteger) and (Length(Nodes[Index].Children) = 1) then
    Index := Nodes[Index].Children[0];
  if (Nodes[Index].Kind <> xakInteger) or not LandrixXmlDecimalTryToInt64(Nodes[Index].Decimal, Result) then
    Result := 0;
end;

{ Removes the items of a pattern from the node FailAt on (patterns use
  forward axes, so node order is axis order), or all of them; on the
  last step of a branch they count as failed. }
procedure TLandrixXmlXPathEvaluator.CutAfterFailure(var S: TLandrixXmlXPathSequence; FailAt: Integer;
  All, Final: Boolean);
var
  I, J: Integer;
begin
  J := 0;
  for I := 0 to S.Count - 1 do
    if not All and (S.Items[I].Node < FailAt) then
    begin
      S.Items[J] := S.Items[I];
      Inc(J);
    end
    else if Final then
      AddFailed(S.Items[I].Node);
  S.Count := J;
end;

{ In a pattern, a predicate failing on an item makes the positions of
  the items after it unknown (FailAt, the first such node; InputFailedAt
  for the input of a filter, MaxInt if none). A later predicate that may
  use the position then sees, as Saxon, which counts a candidate's
  position over the items before it: [k] the k-th item if it comes
  before FailAt (the positions are known again after it) and no item
  otherwise; a predicate calling position() or last() no item; another
  number only the items before FailAt. }
function TLandrixXmlXPathEvaluator.ApplyPredicates(const Predicates: array of Integer;
  const Input: TLandrixXmlXPathSequence; InputFailedAt: Integer): TLandrixXmlXPathSequence;
var
  P, I, Pos, Size, FailAt, Before: Integer;
  K: Int64;
  Current, Next: TLandrixXmlXPathSequence;
  Keep, Pattern, Final, Own: Boolean;
  Ctx: TLandrixXmlXPathSequence;
begin
  Current := Input;
  { a pattern's own predicates: what they contain is evaluated as usual }
  Pattern := FPattern;
  Final := FFinal;
  FPattern := False;
  FailAt := InputFailedAt;
  try
    for P := 0 to Integer(High(Predicates)) do
    begin
      Own := Pattern and (FailAt < MaxInt) and UsesOwnPosition(FNodes, Predicates[P]);
      if Pattern and (FailAt < MaxInt) and (Own or MayBeNumeric(FNodes, Predicates[P])) then
      begin
        { a new sequence: Current may be Input, the storage of a variable }
        Next := LandrixXmlXPathEmpty;
        AppendAll(Next, Current);
        Current := Next;
        K := LiteralPosition(FNodes, Predicates[P]);
        Before := 0;
        for I := 0 to Current.Count - 1 do
          if Current.Items[I].Node < FailAt then
            Inc(Before);
        if Own or (K > Before) then
          CutAfterFailure(Current, FailAt, True, Final)
        else if K > 0 then
          FailAt := MaxInt
        else
          CutAfterFailure(Current, FailAt, False, Final);
      end;
      Next := LandrixXmlXPathEmpty;
      Size := Current.Count;
      for I := 0 to Size - 1 do
      begin
        { the input is in axis order (nearest first on reverse axes) }
        Pos := I + 1;
        Ctx := SingleSeq(Current.Items[I]);
        if not Pattern then
          Keep := PredicateTrue(Eval(Predicates[P], Current.Items[I].Node, Pos, Size, Ctx), Pos)
        else
        begin
          { an error: the item does not match the pattern }
          Keep := False;
          try
            if PredicateTrue(Eval(Predicates[P], Current.Items[I].Node, Pos, Size, Ctx), Pos) then
              Keep := True;
          except
            on E: ELandrixXmlError do
              if PatternMismatch(E) then
              begin
                if Current.Items[I].Node < FailAt then
                  FailAt := Current.Items[I].Node;
                if Final then
                  AddFailed(Current.Items[I].Node);
              end
              else
                raise;
          end;
        end;
        if Keep then
          LandrixXmlXPathAppend(Next, Current.Items[I]);
      end;
      Current := Next;
    end;
    { what is still unknown after the last predicate, for a filter around }
    if Pattern and (FailAt < FMinFailed) then
      FMinFailed := FailAt;
  finally
    FPattern := Pattern;
    FFinal := Final;
  end;
  Result := Current;
end;

{ --- indexes of the steps "name[@attribute = value]" --------------------- }

const
  { fewer or more children of that name: the step is evaluated as usual
    (the upper limit keeps the table size below MaxInt) }
  MinKeyedChildren = 16;
  MaxKeyedChildren = 1 shl 28;
  { more indexes than that in one evaluator: start again }
  MaxKeyIndexes = 4096;

function TKeyIndex.Find(const Value: TLandrixXmlUtf8; Add: Boolean): Integer;
var
  H, Mask: Integer;
begin
  Mask := Integer(Length(Table)) - 1;
  if Value = '' then
    H := Integer(LandrixXmlHashSeed and Cardinal(Mask))
  else
    H := Integer(LandrixXmlHashBytes(PAnsiChar(Value), Length(Value), LandrixXmlHashSeed) and Cardinal(Mask));
  while Table[H] <> 0 do
  begin
    Result := Table[H] - 1;
    if Values[Result] = Value then
      Exit;
    H := (H + 1) and Mask;
  end;
  Result := -1;
  if not Add then
    Exit;
  { the table has more slots than children, Values one per child }
  Result := ValueCount;
  Inc(ValueCount);
  Values[Result] := Value;
  FirstOf[Result] := -1;
  LastOf[Result] := -1;
  Marks[Result] := False;
  Table[H] := Result + 1;
end;

procedure TLandrixXmlXPathEvaluator.DropKeyIndexes;
begin
  if FKeyIndexes <> nil then
    FKeyIndexes.Clear;
  FKeyTable := nil;
end;

{ The index of the children named ChildName of Parent by their attribute
  AttributeName, built on first use. }
function TLandrixXmlXPathEvaluator.FindKeyIndex(Parent, ChildName, AttributeName: Integer): TObject;
var
  H, Mask, I, J, A, K, Count, Size, Local, Base: Integer;
  X: TKeyIndex;
  T: TLandrixXmlXPathTree;

  function Slot: Integer;
  begin
    Result := Integer((Cardinal(Parent) xor (Cardinal(ChildName) shl 11) xor (Cardinal(AttributeName) shl 21)) and
      Cardinal(Mask));
  end;

begin
  if Length(FKeyTable) = 0 then
    SetLength(FKeyTable, 64);
  Mask := Integer(Length(FKeyTable)) - 1;
  H := Slot;
  while FKeyTable[H] <> nil do
  begin
    X := TKeyIndex(FKeyTable[H]);
    if (X.Parent = Parent) and (X.ChildName = ChildName) and (X.AttributeName = AttributeName) then
    begin
      Result := X;
      Exit;
    end;
    H := (H + 1) and Mask;
  end;
  if FKeyIndexes.Count >= MaxKeyIndexes then
  begin
    DropKeyIndexes;
    SetLength(FKeyTable, 64);
    Mask := 63;
    H := Slot;
  end;
  X := TKeyIndex.Create;
  FKeyIndexes.Add(X);
  FKeyTable[H] := X;
  Result := X;
  X.Parent := Parent;
  X.ChildName := ChildName;
  X.AttributeName := AttributeName;
  X.Indexed := False;
  X.ValueCount := 0;
  T := TreeOf(Parent, Base);
  Local := Parent - Base;
  Count := 0;
  I := T.FirstChild(Local);
  while I >= 0 do
  begin
    if (T.Kind[I] = xnkElement) and (T.ExpandedName[I] = ChildName) then
      Inc(Count);
    I := T.NextSibling[I];
  end;
  if (Count >= MinKeyedChildren) and (Count <= MaxKeyedChildren) then
  begin
    Size := 64;
    while Size < 2 * Count do
      Size := 2 * Size;
    SetLength(X.Table, Size);
    for I := 0 to Size - 1 do
      X.Table[I] := 0;
    SetLength(X.Values, Count);
    SetLength(X.FirstOf, Count);
    SetLength(X.LastOf, Count);
    SetLength(X.Marks, Count);
    SetLength(X.Nodes, Count);
    SetLength(X.NextOf, Count);
    J := 0;
    I := T.FirstChild(Local);
    while I >= 0 do
    begin
      if (T.Kind[I] = xnkElement) and (T.ExpandedName[I] = ChildName) then
      begin
        A := I + 1;
        while (A <= I + T.AttributeCount[I]) and
          not ((T.Kind[A] = xnkAttribute) and (T.ExpandedName[A] = AttributeName)) do
          Inc(A);
        if A <= I + T.AttributeCount[I] then
        begin
          K := X.Find(T.StringValueUtf8(A), True);
          X.Nodes[J] := I + Base;
          X.NextOf[J] := -1;
          if X.LastOf[K] >= 0 then
            X.NextOf[X.LastOf[K]] := J
          else
            X.FirstOf[K] := J;
          X.LastOf[K] := J;
          Inc(J);
        end;
      end;
      I := T.NextSibling[I];
    end;
    X.Indexed := True;
  end;
  { at most half full }
  if 2 * FKeyIndexes.Count > Length(FKeyTable) then
  begin
    Count := 2 * Integer(Length(FKeyTable));
    FKeyTable := nil;
    SetLength(FKeyTable, Count);
    Mask := Count - 1;
    for I := 0 to Integer(FKeyIndexes.Count) - 1 do
    begin
      X := TKeyIndex(FKeyIndexes[I]);
      Parent := X.Parent;
      ChildName := X.ChildName;
      AttributeName := X.AttributeName;
      H := Slot;
      while FKeyTable[H] <> nil do
        H := (H + 1) and Mask;
      FKeyTable[H] := X;
    end;
  end;
end;

{ The child step Index from Node through its index, if FindKey found the
  form "name[@attribute = value]" (see TExpressionCache.KeyAttribute).
  The predicate is true for a child exactly when the string of its
  attribute equals one of the values, if they are all strings or
  untypedAtomic (attributes are untypedAtomic; a general comparison of an
  untypedAtomic with a string compares the code points). Returns False
  (and the step is evaluated as usual) for other values, unknown names
  and parents with few such children. The value does not depend on the
  focus, so it is evaluated once instead of once per child; it is only
  evaluated for a parent with at least MinKeyedChildren children of that
  name (the usual evaluation evaluates it for each of them), so an error
  in it is raised exactly when the usual evaluation raises it too. }
function TLandrixXmlXPathEvaluator.KeyedStep(Index, Node: Integer; var Output: TLandrixXmlXPathSequence): Boolean;
var
  C: TExpressionCache;
  T: TLandrixXmlXPathTree;
  X: TKeyIndex;
  Keys: TLandrixXmlXPathSequence;
  Item: TLandrixXmlXPathItem;
  Base, ChildName, AttributeName, I, J, K, Found: Integer;
  Hit: array of Integer;
  Rest: array of Integer;
begin
  Result := False;
  Hit := nil;
  Rest := nil;
  C := TExpressionCache(FCache);
  T := TreeOf(Node, Base);
  ChildName := T.FindExpandedName(FNodes[Index].NamespaceUri, FNodes[Index].LocalName);
  AttributeName := T.FindExpandedName(FNodes[C.KeyAttribute[Index]].NamespaceUri,
    FNodes[C.KeyAttribute[Index]].LocalName);
  if (ChildName < 0) or (AttributeName < 0) then
    Exit;
  if not TKeyIndex(FindKeyIndex(Node, ChildName, AttributeName)).Indexed then
    Exit;
  Keys := Atomize(Eval(C.KeyValue[Index], Node, 1, 1, LandrixXmlXPathEmpty));
  for I := 0 to Keys.Count - 1 do
    if not IsStringLike(Keys.Items[I].Kind) then
      Exit;
  { the evaluation of the value may have started the indexes again }
  X := TKeyIndex(FindKeyIndex(Node, ChildName, AttributeName));
  SetLength(Hit, Keys.Count);
  Found := 0;
  for I := 0 to Keys.Count - 1 do
  begin
    K := X.Find(Keys.Items[I].Text, False);
    if (K >= 0) and not X.Marks[K] then
    begin
      X.Marks[K] := True;
      Hit[Found] := K;
      Inc(Found);
    end;
  end;
  Output := LandrixXmlXPathEmpty;
  InitItem(Item, xikNode);
  for I := 0 to Found - 1 do
  begin
    X.Marks[Hit[I]] := False;
    J := X.FirstOf[Hit[I]];
    while J >= 0 do
    begin
      Item.Node := X.Nodes[J];
      LandrixXmlXPathAppend(Output, Item);
      J := X.NextOf[J];
    end;
  end;
  if Found > 1 then
    SortNodes(Output);
  if Length(FNodes[Index].Predicates) > 1 then
  begin
    SetLength(Rest, Length(FNodes[Index].Predicates) - 1);
    for I := 0 to Integer(High(Rest)) do
      Rest[I] := FNodes[Index].Predicates[I + 1];
    Output := ApplyPredicates(Rest, Output, MaxInt);
  end;
  Result := True;
end;

{ The step Index from Node; Axis is the step's own axis, or descendant
  for a child step that follows "//" (see TExpressionCache.Fuse). }
function TLandrixXmlXPathEvaluator.EvalStep(Index: Integer; Node: Integer;
  Axis: TLandrixXmlXPathAxis): TLandrixXmlXPathSequence;
var
  N: ^TLandrixXmlXPathAstNode;
  Expanded, I, E: Integer;
  Out1: TLandrixXmlXPathSequence;
  Reverse: Boolean;
  Item: TLandrixXmlXPathItem;
  AttributeAxis: Boolean;
  { the node's tree, its numbers from Base on; the step runs in it }
  T: TLandrixXmlXPathTree;
  Base: Integer;

  function Test(I: Integer): Boolean;
  var
    K: TLandrixXmlXPathNodeKind;
  begin
    K := T.Kind[I];
    case N^.NodeTest of
      xntAnyNode: Result := True;
      xntText: Result := K = xnkText;
      xntComment: Result := K = xnkComment;
      xntProcessingInstruction:
        Result := (K = xnkProcessingInstruction) and ((N^.LocalName = '') or (T.LocalNameUtf8(I) = N^.LocalName));
      xntDocumentNode: Result := K = xnkDocument;
      xntAnyElement: Result := K = xnkElement;
      xntAnyAttribute: Result := K = xnkAttribute;
      xntKindTest: Result := NodeMatches(I + Base, N^.SequenceType);
    else
      { name tests: the principal node kind of the axis }
      if AttributeAxis then
        Result := K = xnkAttribute
      else
        Result := K = xnkElement;
      if Result then
        case N^.NodeTest of
          xntName: Result := (Expanded >= 0) and (T.ExpandedName[I] = Expanded);
          xntNamespaceWildcard: Result := T.NamespaceUriUtf8(I) = N^.NamespaceUri;
          xntLocalWildcard: Result := T.LocalNameUtf8(I) = N^.LocalName;
        else
          { * }
        end;
    end;
  end;

  procedure Add(I: Integer);
  begin
    if Test(I) then
    begin
      Item.Node := I + Base;
      LandrixXmlXPathAppend(Out1, Item);
    end;
  end;

  procedure AddDescendants(From: Integer);
  var
    J: Integer;
  begin
    for J := From + 1 to T.SubtreeEnd[From] do
      if T.Kind[J] <> xnkAttribute then
        Add(J);
  end;

begin
  { the result is initialised by the caller (a managed type); Count is
    set so that the compiler sees it written }
  Result.Count := 0;
  if (Axis = xaxChild) and not FPattern and (FCache <> nil) and
    (TExpressionCache(FCache).KeyAttribute[Index] >= 0) and KeyedStep(Index, Node, Result) then
    Exit;
  T := TreeOf(Node, Base);
  Node := Node - Base;
  N := @FNodes[Index];
  Out1 := LandrixXmlXPathEmpty;
  InitItem(Item, xikNode);
  Reverse := False;
  AttributeAxis := Axis = xaxAttribute;
  Expanded := -1;
  if N^.NodeTest = xntName then
    Expanded := T.FindExpandedName(N^.NamespaceUri, N^.LocalName);
  case Axis of
    xaxChild:
      begin
        I := T.FirstChild(Node);
        while I >= 0 do
        begin
          Add(I);
          I := T.NextSibling[I];
        end;
      end;
    xaxDescendant:
      if T.Kind[Node] <> xnkAttribute then
        AddDescendants(Node);
    xaxDescendantOrSelf:
      begin
        Add(Node);
        if T.Kind[Node] <> xnkAttribute then
          AddDescendants(Node);
      end;
    xaxAttribute:
      if T.Kind[Node] = xnkElement then
        for I := Node + 1 to Node + T.AttributeCount[Node] do
          Add(I);
    xaxSelf:
      Add(Node);
    xaxParent:
      if T.Parent[Node] >= 0 then
        Add(T.Parent[Node]);
    xaxAncestor, xaxAncestorOrSelf:
      begin
        Reverse := True;
        if Axis = xaxAncestorOrSelf then
          Add(Node);
        I := T.Parent[Node];
        while I >= 0 do
        begin
          Add(I);
          I := T.Parent[I];
        end;
      end;
    xaxFollowingSibling:
      if T.Kind[Node] <> xnkAttribute then
      begin
        I := T.NextSibling[Node];
        while I >= 0 do
        begin
          Add(I);
          I := T.NextSibling[I];
        end;
      end;
    xaxPrecedingSibling:
      if (T.Kind[Node] <> xnkAttribute) and (T.Parent[Node] >= 0) then
      begin
        Reverse := True;
        { nearest first }
        I := T.FirstChild(T.Parent[Node]);
        E := Out1.Count;
        while (I >= 0) and (I <> Node) do
        begin
          Add(I);
          I := T.NextSibling[I];
        end;
        { reverse what was added }
        for I := 0 to (Out1.Count - E) div 2 - 1 do
        begin
          Item := Out1.Items[E + I];
          Out1.Items[E + I] := Out1.Items[Out1.Count - 1 - I];
          Out1.Items[Out1.Count - 1 - I] := Item;
        end;
      end;
    xaxFollowing:
      begin
        { nodes after Node in document order, without its descendants and
          without attributes (an attribute's parent's children follow it) }
        if T.Kind[Node] = xnkAttribute then
          I := Node + 1
        else
          I := T.SubtreeEnd[Node] + 1;
        for E := I to T.Count - 1 do
          if T.Kind[E] <> xnkAttribute then
            Add(E);
      end;
    xaxPreceding:
      begin
        Reverse := True;
        { nodes before Node in document order, without its ancestors and without attributes }
        I := Node;
        if T.Kind[I] = xnkAttribute then
          I := T.Parent[I];
        E := I - 1;
        while E > 0 do
        begin
          if (T.Kind[E] <> xnkAttribute) and (T.SubtreeEnd[E] < I) then
            Add(E);
          Dec(E);
        end;
      end;
  end;
  if Length(N^.Predicates) > 0 then
    Out1 := ApplyPredicates(N^.Predicates, Out1, MaxInt);
  if Reverse then
    SortNodes(Out1);
  Result := Out1;
end;

{ "intersect" (Op 0) and "except" (Op 1): the nodes of the left operand
  that are, or are not, in the right one, in document order. }
function TLandrixXmlXPathEvaluator.EvalIntersectExcept(Index: Integer; Context, Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  A, B, Other: TLandrixXmlXPathSequence;
  I, J, K: Integer;
begin
  { in a pattern a node an operand failed on would need its own rule (see
    EvaluatePattern); XSLT 2.0 patterns have no intersect and except }
  if FPattern then
    Fail('FOER0000', 'intersect and except in a pattern are not supported');
  A := Eval(FNodes[Index].Children[0], Context, Position, Size, ContextItem);
  B := Eval(FNodes[Index].Children[1], Context, Position, Size, ContextItem);
  for I := 0 to A.Count - 1 do
    if A.Items[I].Kind <> xikNode then
      Fail('XPTY0004', 'the operands of "intersect" and "except" must be nodes');
  for I := 0 to B.Count - 1 do
    if B.Items[I].Kind <> xikNode then
      Fail('XPTY0004', 'the operands of "intersect" and "except" must be nodes');
  { new sequences: A and B may be the storage of variables }
  Result := LandrixXmlXPathEmpty;
  AppendAll(Result, A);
  SortNodes(Result);
  Other := LandrixXmlXPathEmpty;
  AppendAll(Other, B);
  SortNodes(Other);
  J := 0;
  K := 0;
  for I := 0 to Result.Count - 1 do
  begin
    while (J < Other.Count) and (Other.Items[J].Node < Result.Items[I].Node) do
      Inc(J);
    if ((J < Other.Count) and (Other.Items[J].Node = Result.Items[I].Node)) = (FNodes[Index].Op = 0) then
    begin
      Result.Items[K] := Result.Items[I];
      Inc(K);
    end;
  end;
  Result.Count := K;
end;

function TLandrixXmlXPathEvaluator.EvalPath(Index: Integer; Context, Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  N: ^TLandrixXmlXPathAstNode;
  K, I, Step, First: Integer;
  Current, Next, Part, Ctx: TLandrixXmlXPathSequence;
  AllNodes, AllAtomic, Final: Boolean;
  Axis: TLandrixXmlXPathAxis;
begin
  N := @FNodes[Index];
  { in a pattern, only the last step's items are candidates; not restored
    on an exception, which ends EvaluatePattern (code that catches one
    runs with FPattern off and does not use FFinal) }
  Final := FFinal;
  if FPattern then
    FFinal := False;
  if N^.RootStart then
  begin
    if Context < 0 then
      Fail('XPDY0002', 'the context item for "/" is absent or not a node');
    Current := LandrixXmlXPathNodeItem(DocumentRootOf(Context));
    First := 0;
  end
  else
  begin
    Current := Eval(N^.Children[0], Context, Position, Size, ContextItem);
    First := 1;
  end;
  K := First;
  while K <= Integer(High(N^.Children)) do
  begin
    Step := N^.Children[K];
    N := @FNodes[Index];
    Axis := FNodes[Step].Axis;
    { "//" and a child step: the descendants, as one step }
    if (FCache <> nil) and (FNodes[Step].Kind = xakStep) and (Axis = xaxDescendantOrSelf) and
      (FNodes[Step].NodeTest = xntAnyNode) and (Length(FNodes[Step].Predicates) = 0) and
      (K < Integer(High(N^.Children))) and TExpressionCache(FCache).Fuse[N^.Children[K + 1]] then
    begin
      Inc(K);
      Step := N^.Children[K];
      Axis := xaxDescendant;
    end;
    if FPattern then
      FFinal := Final and (K = Integer(High(N^.Children)));
    Next := LandrixXmlXPathEmpty;
    AllNodes := True;
    AllAtomic := True;
    for I := 0 to Current.Count - 1 do
    begin
      if Current.Items[I].Kind <> xikNode then
        Fail('XPTY0019', 'the left side of "/" contains an atomic value');
      if FNodes[Step].Kind = xakStep then
        Part := EvalStep(Step, Current.Items[I].Node, Axis)
      else
      begin
        Ctx := SingleSeq(Current.Items[I]);
        Part := Eval(Step, Current.Items[I].Node, I + 1, Current.Count, Ctx);
      end;
      AppendAll(Next, Part);
    end;
    for I := 0 to Next.Count - 1 do
      if Next.Items[I].Kind = xikNode then
        AllAtomic := False
      else
        AllNodes := False;
    if AllNodes then
      SortNodes(Next)
    else if not AllAtomic then
      Fail('XPTY0018', 'the result of a path contains nodes and atomic values');
    Current := Next;
    Inc(K);
  end;
  if FPattern then
    FFinal := Final;
  Result := Current;
end;

{ for, some, every over bindings Binding .. Count - 2 (the last child is
  the return or satisfies expression). Returns True to stop (some found a
  true item, every a false one). }
function TLandrixXmlXPathEvaluator.EvalQuantified(Index, Binding: Integer; Context, Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; Kind: TLandrixXmlXPathAstKind;
  var Output: TLandrixXmlXPathSequence): Boolean;
var
  Values, V: TLandrixXmlXPathSequence;
  I, Last, Slot: Integer;
  Body: Integer;
begin
  Result := False;
  Last := Integer(High(FNodes[Index].Children));
  if Binding = Last then
  begin
    Body := FNodes[Index].Children[Last];
    V := Eval(Body, Context, Position, Size, ContextItem);
    case Kind of
      xakFor:
        AppendAll(Output, V);
      xakSome:
        Result := SequenceBoolean(V);
      xakEvery:
        Result := not SequenceBoolean(V);
    else
      { not a quantifier }
    end;
    Exit;
  end;
  Values := Eval(FNodes[Index].Children[Binding], Context, Position, Size, ContextItem);
  Slot := FNodes[Index].Slots[Binding];
  for I := 0 to Values.Count - 1 do
  begin
    WriteLocal(Slot, SingleSeq(Values.Items[I]));
    if EvalQuantified(Index, Binding + 1, Context, Position, Size, ContextItem, Kind, Output) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

{ The value of node Index. Only the dispatch is here, in EvalInto: the
  kinds whose evaluation needs temporary sequences, items or strings have
  methods of their own that write the value into Output, so that a call
  does not initialise and finalise the temporaries of every other kind
  (most calls are steps, variables, literals and comparisons in
  predicates). }
function TLandrixXmlXPathEvaluator.Eval(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
begin
  { the result is initialised by the caller (a managed type); Count is
    set so that the compiler sees it written }
  Result.Count := 0;
  EvalInto(Index, Context, Position, Size, ContextItem, Result);
end;

procedure TLandrixXmlXPathEvaluator.EvalInto(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
var
  N: ^TLandrixXmlXPathAstNode;
begin
  { a pattern's steps (not their predicates) are not kept: their value is
    not that of the expression }
  if (FCache <> nil) and (Context >= 0) and (Index <> FBypass) and not FPattern and
    TExpressionCache(FCache).Flags[Index] then
  begin
    CachedInto(Index, Context, Position, Size, ContextItem, Output);
    Exit;
  end;
  FBypass := -1;
  N := @FNodes[Index];
  case N^.Kind of
    xakSequence:
      EvalSequenceExpr(Index, Context, Position, Size, ContextItem, Output);
    xakEmpty:
      begin
        Output.Items := nil;
        Output.Count := 0;
      end;
    xakString, xakInteger, xakDecimal, xakDouble:
      EvalLiteral(Index, Output);
    xakVariable:
      ReadVariableInto(N^.Slot, Output);
    xakContextItem:
      begin
        if ContextItem.Count > 0 then
          Output := ContextItem
        else if Context >= 0 then
          NodeItemInto(Context, Output)
        else
        begin
          Fail('XPDY0002', 'the context item is absent');
          Output.Items := nil;
          Output.Count := 0;
        end;
      end;
    xakRoot:
      begin
        if Context < 0 then
          Fail('XPDY0002', 'the context item for "/" is absent or not a node');
        NodeItemInto(DocumentRootOf(Context), Output);
      end;
    xakStep:
      begin
        { an atomic context item, or none at all }
        if (Context < 0) and (ContextItem.Count > 0) then
          Fail('XPTY0020', 'the context item for an axis step is not a node');
        if Context < 0 then
          Fail('XPDY0002', 'the context item for an axis step is absent');
        StepInto(Index, Context, N^.Axis, Output);
      end;
    xakPath:
      PathInto(Index, Context, Position, Size, ContextItem, Output);
    xakFilter:
      EvalFilter(Index, Context, Position, Size, ContextItem, Output);
    xakFor, xakSome, xakEvery:
      EvalForSomeEvery(Index, Context, Position, Size, ContextItem, Output);
    xakIf:
      EvalIf(Index, Context, Position, Size, ContextItem, Output);
    xakAnd, xakOr:
      EvalAndOr(Index, Context, Position, Size, ContextItem, Output);
    xakGeneralCompare:
      EvalGeneralCompare(Index, Context, Position, Size, ContextItem, Output);
    xakValueCompare, xakRange, xakArithmetic, xakNegate, xakUnaryPlus:
      EvalOperator(Index, Context, Position, Size, ContextItem, Output);
    xakUnion:
      EvalUnion(Index, Context, Position, Size, ContextItem, Output);
    xakIntersectExcept:
      IntersectExceptInto(Index, Context, Position, Size, ContextItem, Output);
    xakNodeCompare:
      EvalNodeCompare(Index, Context, Position, Size, ContextItem, Output);
    xakInstanceOf, xakTreat:
      EvalInstanceTreat(Index, Context, Position, Size, ContextItem, Output);
    xakCast, xakCastable:
      EvalCast(Index, Context, Position, Size, ContextItem, Output);
    xakFunction:
      CallFunctionInto(Index, Context, Position, Size, ContextItem, Output);
  else
    Fail('FOER0000', 'expression kind not supported');
    Output.Items := nil;
    Output.Count := 0;
  end;
end;

{ The calls of EvalInto that go through a function: each has its
  temporary result here, not in EvalInto. }
procedure TLandrixXmlXPathEvaluator.CachedInto(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
begin
  Output := CachedEval(Index, Context, Position, Size, ContextItem);
end;

procedure TLandrixXmlXPathEvaluator.ReadVariableInto(Slot: Integer; var Output: TLandrixXmlXPathSequence);
begin
  Output := ReadVariable(Slot);
end;

procedure TLandrixXmlXPathEvaluator.NodeItemInto(Node: Integer; var Output: TLandrixXmlXPathSequence);
begin
  Output := LandrixXmlXPathNodeItem(Node);
end;

procedure TLandrixXmlXPathEvaluator.StepInto(Index: Integer; Node: Integer; Axis: TLandrixXmlXPathAxis;
  var Output: TLandrixXmlXPathSequence);
begin
  Output := EvalStep(Index, Node, Axis);
end;

procedure TLandrixXmlXPathEvaluator.PathInto(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
begin
  Output := EvalPath(Index, Context, Position, Size, ContextItem);
end;

procedure TLandrixXmlXPathEvaluator.IntersectExceptInto(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
begin
  Output := EvalIntersectExcept(Index, Context, Position, Size, ContextItem);
end;

{ The most frequent functions of the rule sets (not, count, exists,
  normalize-space, string-length, ...) have methods of their own: the
  frame of CallFunction, with its many temporaries and the function name
  for messages, is only set up for the others. }
procedure TLandrixXmlXPathEvaluator.CallFunctionInto(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
begin
  if FNodes[Index].Op >= 0 then
    case TLandrixXmlXPathFunctionId(FNodes[Index].Op) of
      xfnNot, xfnTrue, xfnFalse, xfnBoolean, xfnCount, xfnExists, xfnEmpty:
        begin
          CallBooleanFunction(Index, Context, Position, Size, ContextItem, Output);
          Exit;
        end;
      xfnString, xfnStringLength, xfnNormalizeSpace, xfnUpperCase, xfnLowerCase:
        begin
          CallStringFunction(Index, Context, Position, Size, ContextItem, Output);
          Exit;
        end;
    else
      { the others below }
    end;
  Output := CallFunction(Index, Context, Position, Size, ContextItem);
end;

{ The message of a failed call, outside the callers so that it is no
  temporary there }
procedure FailCall(Id: TLandrixXmlXPathFunctionId; const Code, Detail: string);
begin
  Fail(Code, LandrixXmlXPathFunctionName(Id) + '()' + Detail);
end;

{ not, true, false, boolean, count, exists, empty }
procedure TLandrixXmlXPathEvaluator.CallBooleanFunction(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
var
  Id: TLandrixXmlXPathFunctionId;
  A: TLandrixXmlXPathSequence;
begin
  Id := TLandrixXmlXPathFunctionId(FNodes[Index].Op);
  case Id of
    xfnTrue:
      Output := BooleanSeq(True);
    xfnFalse:
      Output := BooleanSeq(False);
  else
    A := Eval(FNodes[Index].Children[0], Context, Position, Size, ContextItem);
    case Id of
      xfnNot:
        Output := BooleanSeq(not SequenceBoolean(A));
      xfnBoolean:
        Output := BooleanSeq(SequenceBoolean(A));
      xfnCount:
        Output := SingleSeq(IntegerItemOf(A.Count));
      xfnExists:
        Output := BooleanSeq(A.Count > 0);
    else
      Output := BooleanSeq(A.Count = 0);
    end;
  end;
end;

{ The context item of a function without argument }
procedure TLandrixXmlXPathEvaluator.CallContextSeq(Id: TLandrixXmlXPathFunctionId; Context: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
begin
  if ContextItem.Count > 0 then
    Output := ContextItem
  else if Context >= 0 then
    NodeItemInto(Context, Output)
  else
  begin
    FailCall(Id, 'XPDY0002', ': the context item is absent');
    Output.Items := nil;
    Output.Count := 0;
  end;
end;

{ An xs:string? argument: '' for the empty sequence }
function TLandrixXmlXPathEvaluator.CallStrArg(Index, K: Integer; Context, Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlUtf8;
var
  Id: TLandrixXmlXPathFunctionId;
  V: TLandrixXmlXPathSequence;
begin
  Id := TLandrixXmlXPathFunctionId(FNodes[Index].Op);
  V := Atomize(Eval(FNodes[Index].Children[K], Context, Position, Size, ContextItem));
  if V.Count > 1 then
    FailCall(Id, 'XPTY0004', ': argument ' + IntToStr(K + 1) + ' has more than one item');
  Result := '';
  if V.Count = 0 then
    Exit;
  if not IsStringLike(V.Items[0].Kind) then
    FailCall(Id, 'XPTY0004', ': argument ' + IntToStr(K + 1) + ' is ' + KindName(V.Items[0].Kind) +
      ', not xs:string');
  Result := V.Items[0].Text;
end;

{ string, string-length, normalize-space, upper-case, lower-case }
procedure TLandrixXmlXPathEvaluator.CallStringFunction(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
var
  Id: TLandrixXmlXPathFunctionId;
  A: TLandrixXmlXPathSequence;
  S: TLandrixXmlUtf8;
  ArgCount: Integer;
begin
  Id := TLandrixXmlXPathFunctionId(FNodes[Index].Op);
  ArgCount := Integer(Length(FNodes[Index].Children));
  { written by CallContextSeq; the compiler is to see it set }
  A.Count := 0;
  case Id of
    xfnString:
      begin
        if ArgCount = 0 then
          CallContextSeq(Id, Context, ContextItem, A)
        else
          A := Eval(FNodes[Index].Children[0], Context, Position, Size, ContextItem);
        if A.Count > 1 then
          FailCall(Id, 'XPTY0004', ': more than one item');
        if A.Count = 0 then
          Output := LandrixXmlXPathStringItem('')
        else
          Output := LandrixXmlXPathStringItem(StringOf(A.Items[0]));
      end;
    xfnStringLength, xfnNormalizeSpace:
      begin
        if ArgCount = 0 then
        begin
          CallContextSeq(Id, Context, ContextItem, A);
          S := StringOf(A.Items[0]);
        end
        else
          S := CallStrArg(Index, 0, Context, Position, Size, ContextItem);
        if Id = xfnStringLength then
          Output := SingleSeq(IntegerItemOf(CodePointLength(S)))
        else
          Output := LandrixXmlXPathStringItem(NormalizeSpace(S));
      end;
  else
    Output := LandrixXmlXPathStringItem(MapCase(CallStrArg(Index, 0, Context, Position, Size, ContextItem),
      Id = xfnUpperCase));
  end;
end;

procedure TLandrixXmlXPathEvaluator.EvalSequenceExpr(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
var
  A: TLandrixXmlXPathSequence;
  I: Integer;
begin
  Output := LandrixXmlXPathEmpty;
  for I := 0 to Integer(High(FNodes[Index].Children)) do
  begin
    A := Eval(FNodes[Index].Children[I], Context, Position, Size, ContextItem);
    AppendAll(Output, A);
  end;
end;

procedure TLandrixXmlXPathEvaluator.EvalLiteral(Index: Integer; var Output: TLandrixXmlXPathSequence);
var
  N: ^TLandrixXmlXPathAstNode;
begin
  N := @FNodes[Index];
  case N^.Kind of
    xakString:
      Output := LandrixXmlXPathStringItem(N^.Text);
    xakInteger:
      Output := SingleSeq(IntegerItem(N^.Decimal));
    xakDecimal:
      Output := SingleSeq(DecimalItem(N^.Decimal));
  else
    Output := SingleSeq(DoubleItem(N^.DoubleValue));
  end;
end;

procedure TLandrixXmlXPathEvaluator.EvalFilter(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
var
  A: TLandrixXmlXPathSequence;
  Mark, Split: Integer;
begin
  { what the input leaves unknown goes to the predicates, which resolve
    it or pass it on }
  Mark := FMinFailed;
  FMinFailed := MaxInt;
  try
    A := Eval(FNodes[Index].Children[0], Context, Position, Size, ContextItem);
  finally
    Split := FMinFailed;
    FMinFailed := Mark;
  end;
  Output := ApplyPredicates(FNodes[Index].Predicates, A, Split);
end;

procedure TLandrixXmlXPathEvaluator.EvalForSomeEvery(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
var
  Left: Boolean;
begin
  Output := LandrixXmlXPathEmpty;
  Left := EvalQuantified(Index, 0, Context, Position, Size, ContextItem, FNodes[Index].Kind, Output);
  case FNodes[Index].Kind of
    xakSome:
      Output := BooleanSeq(Left);
    xakEvery:
      Output := BooleanSeq(not Left);
  else
    { for: the collected items }
  end;
end;

procedure TLandrixXmlXPathEvaluator.EvalIf(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
var
  A: TLandrixXmlXPathSequence;
begin
  A := Eval(FNodes[Index].Children[0], Context, Position, Size, ContextItem);
  if SequenceBoolean(A) then
    Output := Eval(FNodes[Index].Children[1], Context, Position, Size, ContextItem)
  else
    Output := Eval(FNodes[Index].Children[2], Context, Position, Size, ContextItem);
end;

procedure TLandrixXmlXPathEvaluator.EvalAndOr(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
var
  Left, Right: Boolean;
  LeftError: ELandrixXmlXPathError;
  LeftRaised: Boolean;
  ErrCode, ErrMsg: string;
begin
  { like Saxon: an error in one operand does not matter if the other one
    decides }
  LeftError := nil;
  LeftRaised := False;
  Left := False;
  ErrCode := '';
  ErrMsg := '';
  try
    Left := SequenceBoolean(Eval(FNodes[Index].Children[0], Context, Position, Size, ContextItem));
  except
    on E: ELandrixXmlXPathError do
    begin
      LeftError := E;
      LeftRaised := E is ELandrixXmlXPathRaised;
      ErrCode := E.XPathCode;
      ErrMsg := Copy(E.Message, Length(E.XPathCode) + 3, MaxInt);
    end;
  end;
  if (LeftError = nil) and (Left = (FNodes[Index].Kind = xakOr)) then
  begin
    Output := BooleanSeq(Left);
    Exit;
  end;
  Right := SequenceBoolean(Eval(FNodes[Index].Children[1], Context, Position, Size, ContextItem));
  if LeftError <> nil then
  begin
    if Right = (FNodes[Index].Kind = xakOr) then
    begin
      Output := BooleanSeq(Right);
      Exit;
    end;
    if LeftRaised then
      raise ELandrixXmlXPathRaised.CreateXPath(ErrCode, ErrMsg)
    else
      raise ELandrixXmlXPathError.CreateXPath(ErrCode, ErrMsg);
  end;
  Output := BooleanSeq(Right);
end;

{ "=", "!=", "<", ...: in a procedure of its own, as the most frequent
  operator in predicates }
procedure TLandrixXmlXPathEvaluator.EvalGeneralCompare(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
var
  A, B: TLandrixXmlXPathSequence;
begin
  A := Atomize(Eval(FNodes[Index].Children[0], Context, Position, Size, ContextItem));
  B := Atomize(Eval(FNodes[Index].Children[1], Context, Position, Size, ContextItem));
  Output := BooleanSeq(GeneralCompare(A, B, TLandrixXmlXPathCompare(FNodes[Index].Op), Xp20, FImplicitTimeZone,
    FExpr));
end;

{ The value comparisons, the range and the arithmetic operators }
procedure TLandrixXmlXPathEvaluator.EvalOperator(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
var
  A, B: TLandrixXmlXPathSequence;
begin
  A := Atomize(Eval(FNodes[Index].Children[0], Context, Position, Size, ContextItem));
  if FNodes[Index].Kind in [xakNegate, xakUnaryPlus] then
  begin
    if A.Count = 0 then
      Output := LandrixXmlXPathEmpty
    else
    begin
      if A.Count > 1 then
        Fail('XPTY0004', 'a unary minus needs a single item');
      Output := SingleSeq(UnaryOp(A.Items[0], FNodes[Index].Kind = xakNegate, Xp20));
    end;
    Exit;
  end;
  B := Atomize(Eval(FNodes[Index].Children[1], Context, Position, Size, ContextItem));
  case FNodes[Index].Kind of
    xakValueCompare:
      if (A.Count = 0) or (B.Count = 0) then
        Output := LandrixXmlXPathEmpty
      else
      begin
        if (A.Count > 1) or (B.Count > 1) then
          Fail('XPTY0004', 'a value comparison needs single items');
        Output := BooleanSeq(ValueCompare(A.Items[0], B.Items[0], TLandrixXmlXPathCompare(FNodes[Index].Op),
          Xp20, FImplicitTimeZone));
      end;
    xakRange:
      Output := RangeOf(A, B, Xp20);
  else
    if (A.Count = 0) or (B.Count = 0) then
      Output := LandrixXmlXPathEmpty
    else
    begin
      if (A.Count > 1) or (B.Count > 1) then
        Fail('XPTY0004', 'arithmetic needs single items');
      Output := SingleSeq(Arithmetic(A.Items[0], B.Items[0], TLandrixXmlXPathArithmetic(FNodes[Index].Op), Xp20,
        FImplicitTimeZone));
    end;
  end;
end;

procedure TLandrixXmlXPathEvaluator.EvalUnion(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
var
  A, B: TLandrixXmlXPathSequence;
  I, Mark, Split: Integer;
begin
  Mark := FFailedCount;
  A := Eval(FNodes[Index].Children[0], Context, Position, Size, ContextItem);
  Split := FFailedCount;
  B := Eval(FNodes[Index].Children[1], Context, Position, Size, ContextItem);
  for I := 0 to A.Count - 1 do
    if A.Items[I].Kind <> xikNode then
      Fail('XPTY0004', 'the operands of "|" must be nodes');
  for I := 0 to B.Count - 1 do
    if B.Items[I].Kind <> xikNode then
      Fail('XPTY0004', 'the operands of "|" must be nodes');
  { a pattern: a node the left side failed on does not match, as Saxon
    tries the branches in order }
  if FPattern and (Split > Mark) then
    B := WithoutFailed(B, Mark, Split);
  { a new sequence: A may be the storage of a variable }
  Output := LandrixXmlXPathEmpty;
  AppendAll(Output, A);
  AppendAll(Output, B);
  SortNodes(Output);
end;

procedure TLandrixXmlXPathEvaluator.EvalNodeCompare(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
var
  A, B: TLandrixXmlXPathSequence;
begin
  A := Eval(FNodes[Index].Children[0], Context, Position, Size, ContextItem);
  B := Eval(FNodes[Index].Children[1], Context, Position, Size, ContextItem);
  if (A.Count = 0) or (B.Count = 0) then
    Output := LandrixXmlXPathEmpty
  else
  begin
    if (A.Count > 1) or (B.Count > 1) or (A.Items[0].Kind <> xikNode) or (B.Items[0].Kind <> xikNode) then
      Fail('XPTY0004', 'a node comparison needs single nodes');
    { node numbers are in document order, also across documents }
    case TLandrixXmlXPathCompare(FNodes[Index].Op) of
      xpcLt: Output := BooleanSeq(A.Items[0].Node < B.Items[0].Node);
      xpcGt: Output := BooleanSeq(A.Items[0].Node > B.Items[0].Node);
    else
      Output := BooleanSeq(A.Items[0].Node = B.Items[0].Node);
    end;
  end;
end;

procedure TLandrixXmlXPathEvaluator.EvalInstanceTreat(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
var
  A: TLandrixXmlXPathSequence;
  N: ^TLandrixXmlXPathAstNode;
begin
  if FNodes[Index].Kind = xakInstanceOf then
  begin
    A := Eval(FNodes[Index].Children[0], Context, Position, Size, ContextItem);
    N := @FNodes[Index];
    Output := BooleanSeq(SequenceMatches(A, N^.SequenceType));
  end
  else
  begin
    Output := Eval(FNodes[Index].Children[0], Context, Position, Size, ContextItem);
    N := @FNodes[Index];
    if not SequenceMatches(Output, N^.SequenceType) then
      Fail('XPDY0050', 'treat as ' + LandrixXmlXPathSequenceTypeName(N^.SequenceType) +
        ': the value does not match');
  end;
end;

procedure TLandrixXmlXPathEvaluator.EvalCast(Index: Integer; Context: Integer; Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence; var Output: TLandrixXmlXPathSequence);
var
  A: TLandrixXmlXPathSequence;
  N: ^TLandrixXmlXPathAstNode;
begin
  A := Atomize(Eval(FNodes[Index].Children[0], Context, Position, Size, ContextItem));
  N := @FNodes[Index];
  if N^.Kind = xakCastable then
  begin
    if A.Count = 0 then
      Output := BooleanSeq(N^.AllowEmpty)
    else if A.Count > 1 then
      Output := BooleanSeq(False)
    else if N^.AtomicType = xikQName then
      Output := BooleanSeq(CastableToQName(A.Items[0], FExpr, Xp20, FNodes[N^.Children[0]].Kind = xakString))
    else
      Output := BooleanSeq(Castable(A.Items[0], N^.AtomicType, Xp20));
  end
  else if A.Count = 0 then
  begin
    if not N^.AllowEmpty then
      Fail('XPTY0004', 'an empty sequence cannot be cast to ' + LandrixXmlXPathAtomicTypeName(N^.AtomicType));
    Output := LandrixXmlXPathEmpty;
  end
  else
  begin
    if A.Count > 1 then
      Fail('XPTY0004', 'a sequence of several items cannot be cast');
    if N^.AtomicType = xikQName then
      Output := SingleSeq(CastToQName(A.Items[0], FExpr, Xp20, FNodes[N^.Children[0]].Kind = xakString))
    else
      Output := SingleSeq(CastTo(A.Items[0], N^.AtomicType, Xp20));
  end;
end;

{ Function conversion rules: the argument (or result) converted to the
  declared type: atomized, untypedAtomic cast to the atomic type,
  cardinality checked. }
function TLandrixXmlXPathEvaluator.CallUser(Def: TLandrixXmlXPathFunctionDef;
  const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  SavedFrame: TLandrixXmlXPathSlots;
  SavedCurrent, I: Integer;
  SavedPattern: Boolean;
  SavedExpr: TLandrixXmlXPathExpression;
  SavedBase: Integer;
  Empty: TLandrixXmlXPathSequence;
begin
  if FDepth >= FMaxDepth then
    Fail('FOER0000', 'user functions nested deeper than ' + IntToStr(FMaxDepth));
  Inc(FDepth);
  SavedFrame := FFrame;
  SavedCurrent := FCurrentNode;
  SavedPattern := FPattern;
  { no current() inside a function, as in XSLT; its body is no pattern }
  FCurrentNode := -1;
  FPattern := False;
  FFrame := nil;
  try
    SetLength(FFrame, Def.FrameSize);
    for I := 0 to Def.FrameSize - 1 do
      ClearSlot(FFrame[I]);
    for I := 0 to Integer(High(Args)) do
    begin
      FFrame[Def.ParamSlots[I]].State := xssValue;
      FFrame[Def.ParamSlots[I]].Value := ConvertTo(Args[I], Def.ParamTypes[I], Def.Name,
        Def.Body.Profile = xppXPath20);
    end;
    for I := 0 to Integer(Length(Def.LocalSlots)) - 1 do
    begin
      FFrame[Def.LocalSlots[I]].State := xssLazy;
      FFrame[Def.LocalSlots[I]].Expression := Def.LocalExpressions[I];
      FFrame[Def.LocalSlots[I]].ContextNode := -1;
      if I < Length(Def.LocalTypes) then
        FFrame[Def.LocalSlots[I]].DeclaredType := Def.LocalTypes[I];
    end;
    Empty := LandrixXmlXPathEmpty;
    EnterExpression(Def.Body, SavedExpr, SavedBase);
    try
      Result := Eval(Def.Body.Root, -1, 0, 0, Empty);
    finally
      LeaveExpression(SavedExpr, SavedBase);
    end;
    Result := ConvertTo(Result, Def.ResultType, Def.Name, Def.Body.Profile = xppXPath20);
  finally
    FFrame := SavedFrame;
    FCurrentNode := SavedCurrent;
    FPattern := SavedPattern;
    Dec(FDepth);
  end;
end;

{ A user function the caller implements; nested calls count towards
  MaxDepth as those of other user functions. }
function TLandrixXmlXPathEvaluator.CallHost(Def: TLandrixXmlXPathFunctionDef;
  const Args: array of TLandrixXmlXPathSequence; Context, Position, Size: Integer;
  const ContextItem: TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  Focus: TLandrixXmlXPathFocus;
  SavedPattern, SavedFinal: Boolean;
begin
  if FDepth >= FMaxDepth then
    Fail('FOER0000', 'user functions nested deeper than ' + IntToStr(FMaxDepth));
  { the focus as EvaluateInFocus takes it: a context node is never also
    the item (predicates and steps pass both) }
  Focus.Node := Context;
  Focus.Item := ContextItem;
  if (ContextItem.Count = 1) and (ContextItem.Items[0].Kind = xikNode) then
    Focus.Node := ContextItem.Items[0].Node;
  if Focus.Node >= 0 then
    Focus.Item := LandrixXmlXPathEmpty;
  Focus.Position := Position;
  Focus.Size := Size;
  { what the function evaluates is no pattern (as in CallUser) }
  SavedPattern := FPattern;
  SavedFinal := FFinal;
  FPattern := False;
  FFinal := False;
  Inc(FDepth);
  try
    Result := Def.Host(Self, Def, Args, Focus);
  finally
    Dec(FDepth);
    FPattern := SavedPattern;
    FFinal := SavedFinal;
  end;
end;

{$I LandrixXmlXPathFunctions.inc}

function LandrixXmlXPathResolveUri(const Relative, Base: TLandrixXmlUtf8): TLandrixXmlUtf8;
begin
  Result := ResolveUriReference(Relative, Base);
end;

function LandrixXmlXPathNodeBaseUri(Tree: TLandrixXmlXPathTree; Node: Integer; out Uri: TLandrixXmlUtf8): Boolean;
begin
  Result := NodeBaseUri(Tree, Node, Uri);
end;

end.
