{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  XPath 2.0 expressions: lexer, parser and syntax tree, for the evaluator
  in LandrixXmlXPathEval. The supported language is the part of XPath 2.0
  the EN16931, XRechnung, Peppol and Factur-X rule sets use (see the
  phase 0 inventory): path expressions on all axes except namespace and
  following, predicates, the operators (general and value comparisons,
  arithmetic, to, union), for, some, every, if, cast as and castable as
  with an optional "?", literals, variables and function calls. Anything
  else of XPath 2.0 (instance of, treat as, intersect, except, is, << and
  >>, the namespace and following axes, element() and attribute() tests
  with arguments, schema-element(), typeswitch is not XPath 2.0) is
  rejected when the expression is compiled, with the XPath error code
  XPST0003 and the position, never ignored. Functions take no collation
  argument (only the code point collation exists).

  Names in the expression are resolved when it is compiled, with the
  namespaces of the static context: an unprefixed name test means no
  namespace (no default element namespace, as in Schematron), an
  unprefixed function name the XPath function namespace. Variables and
  user functions must be declared in the static context; each variable
  becomes a slot number. Static errors raise ELandrixXmlXPathError with the
  W3C code (XPST0003 syntax, XPST0008 unknown variable, XPST0017 unknown
  function or wrong number of arguments, XPST0051 unknown type, XPST0081
  unknown prefix). }

unit LandrixXmlXPath;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlDecimal,
  LandrixXmlDouble;

const
  LandrixXmlXPathFunctionNamespace = 'http://www.w3.org/2005/xpath-functions';
  LandrixXmlXPathSchemaNamespace = 'http://www.w3.org/2001/XMLSchema';

type
  { An XPath error: Code is the W3C error code (XPST0003, FORG0001, ...). }
  ELandrixXmlXPathError = class(ELandrixXmlError)
  private
    FXPathCode: string;
  public
    constructor CreateXPath(const AXPathCode, Msg: string);
    property XPathCode: string read FXPathCode;
  end;

  TLandrixXmlXPathAstKind = (
    xakSequence,      { E1, E2, ...: Children }
    xakEmpty,         { () }
    xakFor,           { for: Children = binding expressions, last = return; Slots }
    xakSome,          { some: as for, last = satisfies }
    xakEvery,
    xakIf,            { Children = condition, then, else }
    xakOr,            { Children = left, right }
    xakAnd,
    xakGeneralCompare, { Op = TLandrixXmlXPathCompare }
    xakValueCompare,
    xakRange,         { to }
    xakArithmetic,    { Op = TLandrixXmlXPathArithmetic }
    xakUnion,
    xakIntersectExcept, { Op = 0 intersect, 1 except }
    xakNodeCompare,   { Op = xpcEq for is, xpcLt for <<, xpcGt for >> }
    xakNegate,        { unary minus; unary plus is xakUnaryPlus }
    xakUnaryPlus,
    xakCast,          { Children = operand; AtomicType, AllowEmpty }
    xakCastable,
    xakRoot,          { / alone: the root of the context node }
    xakPath,          { Children = first, step, step ...; RootStart: begins at the root }
    xakStep,          { Axis, NodeTest; Predicates }
    xakFilter,        { Children = primary; Predicates }
    xakString,        { Text }
    xakInteger,       { Decimal (integral) }
    xakDecimal,       { Decimal }
    xakDouble,        { DoubleValue }
    xakVariable,      { Slot }
    xakContextItem,   { . }
    xakFunction,      { Op = function id (built-in) or -1 - user function index; Children = arguments }
    xakLet            { internal binding: Slot, Children = value, body }
  );

  TLandrixXmlXPathCompare = (xpcEq, xpcNe, xpcLt, xpcLe, xpcGt, xpcGe);
  TLandrixXmlXPathArithmetic = (xpaAdd, xpaSubtract, xpaMultiply, xpaDivide, xpaIntegerDivide, xpaModulo);

  TLandrixXmlXPathAxis = (xaxChild, xaxDescendant, xaxAttribute, xaxSelf, xaxDescendantOrSelf,
    xaxFollowingSibling, xaxParent, xaxAncestor, xaxPrecedingSibling, xaxPreceding,
    xaxAncestorOrSelf, xaxFollowing);

  { node tests: any node; a kind; names (uri + local, uri:*, *:local, *) }
  TLandrixXmlXPathNodeTest = (xntAnyNode, xntText, xntComment, xntProcessingInstruction,
    xntDocumentNode, xntAnyElement, xntAnyAttribute, xntName, xntNamespaceWildcard, xntLocalWildcard,
    xntAnyName);

  { The type labels: the kind of an item (a node or an atomic value) and
    the atomic type of a cast, a constructor function or a parameter. The
    list grows with the supported types; new labels are appended. Items
    have the kinds xikNode to xikTime; xikFloat (no xs:float values yet),
    xikAnyAtomic (abstract) and xikNone (no type) only label types. }
  TLandrixXmlXPathItemKind = (xikNode, xikUntypedAtomic, xikString, xikAnyUri, xikBoolean, xikInteger,
    xikDecimal, xikDouble, xikDate, xikDateTime, xikTime, xikFloat, xikAnyAtomic, xikNone);

  { Sequence types: the declared type of a variable, parameter or function
    result. Occurrence: exactly one, ?, * and +. }
  TLandrixXmlXPathOccurrence = (xocOne, xocOptional, xocMany, xocOneOrMore);
  { item(), a kind test, an atomic type, empty-sequence() }
  TLandrixXmlXPathTypeKind = (xtkAnyItem, xtkNode, xtkAtomic, xtkEmpty);
  { the kind tests: node(), document-node(), element(), attribute(),
    text(), comment(), processing-instruction() }
  TLandrixXmlXPathKindTest = (xktAnyNode, xktDocument, xktElement, xktAttribute, xktText, xktComment,
    xktProcessingInstruction);
  TLandrixXmlXPathSequenceType = record
    Kind: TLandrixXmlXPathTypeKind;
    { xtkAtomic }
    AtomicType: TLandrixXmlXPathItemKind;
    { xtkNode }
    KindTest: TLandrixXmlXPathKindTest;
    { the name of element(N), attribute(N) and processing-instruction(N),
      empty LocalName for any name }
    NamespaceUri: TLandrixXmlUtf8;
    LocalName: TLandrixXmlUtf8;
    { element(N, T) and attribute(N, T): the local name of T in the xs
      namespace, empty if none }
    ContentType: TLandrixXmlUtf8;
    { element(N, T?) }
    Nilled: Boolean;
    { document-node(element(...)): NamespaceUri, LocalName, ContentType
      and Nilled describe the element }
    ElementTest: Boolean;
    Occurrence: TLandrixXmlXPathOccurrence;
    { False: no "as", anything goes }
    Declared: Boolean;
  end;

  TLandrixXmlXPathAstNode = record
    Kind: TLandrixXmlXPathAstKind;
    Op: Integer;
    Children: array of Integer;
    Predicates: array of Integer;
    Slots: array of Integer;
    Slot: Integer;
    Axis: TLandrixXmlXPathAxis;
    NodeTest: TLandrixXmlXPathNodeTest;
    { name test: namespace URI and local name; a processing-instruction()
      test with a target has it in LocalName }
    NamespaceUri: TLandrixXmlUtf8;
    LocalName: TLandrixXmlUtf8;
    RootStart: Boolean;
    Text: TLandrixXmlUtf8;
    Decimal: TLandrixXmlDecimal;
    DoubleValue: TLandrixXmlDouble;
    AtomicType: TLandrixXmlXPathItemKind;
    AllowEmpty: Boolean;
    { 1-based byte index into the expression text (messages print it
      0-based as "offset") }
    Position: Integer;
  end;
  TLandrixXmlXPathAstNodes = array of TLandrixXmlXPathAstNode;

  { The built-in functions (XPath functions, XSLT's current(), and the
    constructor functions of the xs: types). }
  TLandrixXmlXPathFunctionId = (
    xfnNot, xfnTrue, xfnFalse, xfnBoolean, xfnCount, xfnSum, xfnAvg, xfnMin, xfnMax,
    xfnExists, xfnEmpty, xfnString, xfnStringLength, xfnNormalizeSpace, xfnConcat, xfnStringJoin,
    xfnSubstring, xfnSubstringBefore, xfnSubstringAfter, xfnContains, xfnStartsWith, xfnEndsWith,
    xfnUpperCase, xfnLowerCase, xfnTranslate, xfnMatches, xfnReplace, xfnTokenize,
    xfnStringToCodepoints, xfnCodepointsToString, xfnNumber, xfnAbs, xfnRound, xfnRoundHalfToEven,
    xfnFloor, xfnCeiling, xfnName, xfnLocalName, xfnNamespaceUri, xfnRoot, xfnPosition, xfnLast,
    xfnReverse, xfnDistinctValues, xfnSubsequence, xfnIndexOf, xfnData, xfnExactlyOne,
    xfnZeroOrOne, xfnOneOrMore, xfnCurrent, xfnDocument,
    xfnXsString, xfnXsBoolean, xfnXsDecimal, xfnXsInteger, xfnXsDouble, xfnXsFloat, xfnXsDate,
    xfnXsDateTime, xfnXsTime, xfnXsAnyUri, xfnXsUntypedAtomic
  );

  { A user function (Schematron rule sets declare them): name, parameter
    count; the caller keeps the rest. }
  TLandrixXmlXPathUserFunction = record
    NamespaceUri: TLandrixXmlUtf8;
    LocalName: TLandrixXmlUtf8;
    Arity: Integer;
  end;

  { The language an expression is compiled and evaluated for.
    xppXPath20: XPath 2.0 as specified (the function signatures, casting
    and argument rules of XPath 2.0 and XML Schema 1.0).
    xppSaxon: Saxon HE 12 as the KoSIT validator runs XPath 2.0 rule sets
    (it applies XPath 3.1 rules: round and string-join with other
    arities, string-join on any atomic values, XML Schema 1.1 lexical
    forms, Java's conversion of large doubles to integers). }
  TLandrixXmlXPathProfile = (xppXPath20, xppSaxon);

  { Namespaces, variables and user functions an expression may use. Not
    thread-safe while declarations are added; compiling only reads it. }
  TLandrixXmlXPathStaticContext = class
  private
    FProfile: TLandrixXmlXPathProfile;
    FPrefixes: TLandrixXmlUtf8Array;
    FUris: TLandrixXmlUtf8Array;
    FVariables: TLandrixXmlUtf8Array;
    FFunctions: array of TLandrixXmlXPathUserFunction;
    function GetVariableCount: Integer;
    function GetFunctionCount: Integer;
  public
    { the xml and xs prefixes are predeclared; fn too }
    constructor Create;
    procedure AddNamespace(const Prefix, NamespaceUri: TLandrixXmlUtf8);
    function LookupNamespace(const Prefix: TLandrixXmlUtf8; out NamespaceUri: TLandrixXmlUtf8): Boolean;
    { A variable by its name as written after "$" (a prefix is resolved
      when the expression refers to it); returns its slot. Declaring a
      name again gives the existing slot. }
    function DeclareVariable(const Name: TLandrixXmlUtf8): Integer;
    function FindVariable(const NamespaceUri, LocalName: TLandrixXmlUtf8): Integer;
    { returns the function's index }
    function DeclareFunction(const NamespaceUri, LocalName: TLandrixXmlUtf8; Arity: Integer): Integer;
    function FindFunction(const NamespaceUri, LocalName: TLandrixXmlUtf8; Arity: Integer): Integer;
    property VariableCount: Integer read GetVariableCount;
    property FunctionCount: Integer read GetFunctionCount;
    { xppXPath20 unless set; every expression keeps the profile it was
      compiled with }
    property Profile: TLandrixXmlXPathProfile read FProfile write FProfile;
  end;

  { A compiled expression; immutable, usable from several threads. }
  TLandrixXmlXPathExpression = class
  private
    FText: TLandrixXmlUtf8;
    FNodes: TLandrixXmlXPathAstNodes;
    FRoot: Integer;
    FSlotCount: Integer;
    FFirstLocalSlot: Integer;
    FSerial: Int64;
    FProfile: TLandrixXmlXPathProfile;
    function GetNode(Index: Integer): TLandrixXmlXPathAstNode;
    function GetNodeCount: Integer;
  public
    { Compiles Text. Context may be nil (no namespaces besides xml, xs and
      fn, no variables, no user functions, profile xppXPath20). Raises
      ELandrixXmlXPathError. }
    constructor Create(const Text: TLandrixXmlUtf8; Context: TLandrixXmlXPathStaticContext);
    property Text: TLandrixXmlUtf8 read FText;
    property Root: Integer read FRoot;
    property Nodes[Index: Integer]: TLandrixXmlXPathAstNode read GetNode;
    { all nodes, for the evaluator (do not change them) }
    property NodeArray: TLandrixXmlXPathAstNodes read FNodes;
    property NodeCount: Integer read GetNodeCount;
    { the number of variable slots: the static context's variables, then
      those of for, some and every in the expression }
    property SlotCount: Integer read FSlotCount;
    { the first slot of for, some and every (the static context's
      variable count when compiled) }
    property FirstLocalSlot: Integer read FFirstLocalSlot;
    { a number counted up (under a lock) for every expression created, so
      that no two expressions of a process share it: it tells an
      expression from a later one at the same address (the evaluator
      keeps values per expression) }
    property Serial: Int64 read FSerial;
    { the static context's profile when compiled }
    property Profile: TLandrixXmlXPathProfile read FProfile;
  end;

  { The name and number of arguments of a built-in function, for messages
    and the evaluator. }
function LandrixXmlXPathFunctionName(Id: TLandrixXmlXPathFunctionId): string;
{ "xs:" and the local name of an atomic type; "node()" for xikNode. }
function LandrixXmlXPathAtomicTypeName(T: TLandrixXmlXPathItemKind): string;
{ The atomic type with this local name in the xs namespace; xikNone if it
  is not supported. }
function LandrixXmlXPathAtomicTypeByName(const LocalName: TLandrixXmlUtf8): TLandrixXmlXPathItemKind;

{ Parses an XPath 2.0 SequenceType ("xs:decimal?", "element(a)*",
  "document-node(element(*, xs:untyped))", "empty-sequence()"); the
  prefixes are Context's (nil: xml, xs and fn). Raises
  ELandrixXmlXPathError (XPST0003 syntax, XPST0081 prefix, XPST0051
  unknown or unsupported atomic type, XPST0008 unknown type name or
  schema-element()). }
function LandrixXmlXPathParseSequenceType(const Text: TLandrixXmlUtf8;
  Context: TLandrixXmlXPathStaticContext): TLandrixXmlXPathSequenceType;
{ A sequence type as XPath writes it, for messages (a name in a
  namespace as Q, the URI in curly brackets, and the local name). }
function LandrixXmlXPathSequenceTypeName(const T: TLandrixXmlXPathSequenceType): string;

implementation

var
  ExpressionCounter: Int64 = 0;
  CounterLock: TMultiReadExclusiveWriteSynchronizer;

type
  TFunctionInfo = record
    Name: string;
    MinArgs: Integer;
    MaxArgs: Integer; { -1: any number }
    Xs: Boolean;
  end;

const
  Functions: array[TLandrixXmlXPathFunctionId] of TFunctionInfo = (
    (Name: 'not'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'true'; MinArgs: 0; MaxArgs: 0; Xs: False),
    (Name: 'false'; MinArgs: 0; MaxArgs: 0; Xs: False),
    (Name: 'boolean'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'count'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'sum'; MinArgs: 1; MaxArgs: 2; Xs: False),
    (Name: 'avg'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'min'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'max'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'exists'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'empty'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'string'; MinArgs: 0; MaxArgs: 1; Xs: False),
    (Name: 'string-length'; MinArgs: 0; MaxArgs: 1; Xs: False),
    (Name: 'normalize-space'; MinArgs: 0; MaxArgs: 1; Xs: False),
    (Name: 'concat'; MinArgs: 2; MaxArgs: -1; Xs: False),
    (Name: 'string-join'; MinArgs: 1; MaxArgs: 2; Xs: False),
    (Name: 'substring'; MinArgs: 2; MaxArgs: 3; Xs: False),
    (Name: 'substring-before'; MinArgs: 2; MaxArgs: 2; Xs: False),
    (Name: 'substring-after'; MinArgs: 2; MaxArgs: 2; Xs: False),
    (Name: 'contains'; MinArgs: 2; MaxArgs: 2; Xs: False),
    (Name: 'starts-with'; MinArgs: 2; MaxArgs: 2; Xs: False),
    (Name: 'ends-with'; MinArgs: 2; MaxArgs: 2; Xs: False),
    (Name: 'upper-case'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'lower-case'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'translate'; MinArgs: 3; MaxArgs: 3; Xs: False),
    (Name: 'matches'; MinArgs: 2; MaxArgs: 3; Xs: False),
    (Name: 'replace'; MinArgs: 3; MaxArgs: 4; Xs: False),
    (Name: 'tokenize'; MinArgs: 2; MaxArgs: 3; Xs: False),
    (Name: 'string-to-codepoints'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'codepoints-to-string'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'number'; MinArgs: 0; MaxArgs: 1; Xs: False),
    (Name: 'abs'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'round'; MinArgs: 1; MaxArgs: 2; Xs: False),
    (Name: 'round-half-to-even'; MinArgs: 1; MaxArgs: 2; Xs: False),
    (Name: 'floor'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'ceiling'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'name'; MinArgs: 0; MaxArgs: 1; Xs: False),
    (Name: 'local-name'; MinArgs: 0; MaxArgs: 1; Xs: False),
    (Name: 'namespace-uri'; MinArgs: 0; MaxArgs: 1; Xs: False),
    (Name: 'root'; MinArgs: 0; MaxArgs: 1; Xs: False),
    (Name: 'position'; MinArgs: 0; MaxArgs: 0; Xs: False),
    (Name: 'last'; MinArgs: 0; MaxArgs: 0; Xs: False),
    (Name: 'reverse'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'distinct-values'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'subsequence'; MinArgs: 2; MaxArgs: 3; Xs: False),
    (Name: 'index-of'; MinArgs: 2; MaxArgs: 2; Xs: False),
    (Name: 'data'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'exactly-one'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'zero-or-one'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'one-or-more'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'current'; MinArgs: 0; MaxArgs: 0; Xs: False),
    (Name: 'document'; MinArgs: 1; MaxArgs: 1; Xs: False),
    (Name: 'string'; MinArgs: 1; MaxArgs: 1; Xs: True),
    (Name: 'boolean'; MinArgs: 1; MaxArgs: 1; Xs: True),
    (Name: 'decimal'; MinArgs: 1; MaxArgs: 1; Xs: True),
    (Name: 'integer'; MinArgs: 1; MaxArgs: 1; Xs: True),
    (Name: 'double'; MinArgs: 1; MaxArgs: 1; Xs: True),
    (Name: 'float'; MinArgs: 1; MaxArgs: 1; Xs: True),
    (Name: 'date'; MinArgs: 1; MaxArgs: 1; Xs: True),
    (Name: 'dateTime'; MinArgs: 1; MaxArgs: 1; Xs: True),
    (Name: 'time'; MinArgs: 1; MaxArgs: 1; Xs: True),
    (Name: 'anyURI'; MinArgs: 1; MaxArgs: 1; Xs: True),
    (Name: 'untypedAtomic'; MinArgs: 1; MaxArgs: 1; Xs: True)
  );

  { local names in the xs namespace; empty for the labels without one }
  AtomicNames: array[TLandrixXmlXPathItemKind] of string = ('', 'untypedAtomic', 'string', 'anyURI',
    'boolean', 'integer', 'decimal', 'double', 'date', 'dateTime', 'time', 'float', 'anyAtomicType', '');

function LandrixXmlXPathFunctionName(Id: TLandrixXmlXPathFunctionId): string;
begin
  if Functions[Id].Xs then
    Result := 'xs:' + Functions[Id].Name
  else
    Result := Functions[Id].Name;
end;

function LandrixXmlXPathAtomicTypeName(T: TLandrixXmlXPathItemKind): string;
begin
  if T = xikNode then
    Result := 'node()'
  else
    Result := 'xs:' + AtomicNames[T];
end;

function LandrixXmlXPathAtomicTypeByName(const LocalName: TLandrixXmlUtf8): TLandrixXmlXPathItemKind;
var
  T: TLandrixXmlXPathItemKind;
begin
  for T := Low(TLandrixXmlXPathItemKind) to High(TLandrixXmlXPathItemKind) do
    if (AtomicNames[T] <> '') and (LandrixXmlStringToUtf8(AtomicNames[T]) = LocalName) then
    begin
      Result := T;
      Exit;
    end;
  Result := xikNone;
end;

{ --- ELandrixXmlXPathError --------------------------------------------- }

constructor ELandrixXmlXPathError.CreateXPath(const AXPathCode, Msg: string);
begin
  inherited CreateCode(xecXPath, AXPathCode + ': ' + Msg);
  FXPathCode := AXPathCode;
end;

{ --- TLandrixXmlXPathStaticContext ------------------------------------- }

constructor TLandrixXmlXPathStaticContext.Create;
begin
  inherited Create;
  AddNamespace('xml', 'http://www.w3.org/XML/1998/namespace');
  AddNamespace('xs', LandrixXmlXPathSchemaNamespace);
  AddNamespace('fn', LandrixXmlXPathFunctionNamespace);
end;

procedure TLandrixXmlXPathStaticContext.AddNamespace(const Prefix, NamespaceUri: TLandrixXmlUtf8);
var
  I: Integer;
begin
  for I := 0 to Integer(Length(FPrefixes)) - 1 do
    if FPrefixes[I] = Prefix then
    begin
      FUris[I] := NamespaceUri;
      Exit;
    end;
  SetLength(FPrefixes, Length(FPrefixes) + 1);
  SetLength(FUris, Length(FUris) + 1);
  FPrefixes[High(FPrefixes)] := Prefix;
  FUris[High(FUris)] := NamespaceUri;
end;

function TLandrixXmlXPathStaticContext.LookupNamespace(const Prefix: TLandrixXmlUtf8;
  out NamespaceUri: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  for I := 0 to Integer(Length(FPrefixes)) - 1 do
    if FPrefixes[I] = Prefix then
    begin
      NamespaceUri := FUris[I];
      Result := True;
      Exit;
    end;
  NamespaceUri := '';
  Result := False;
end;

function TLandrixXmlXPathStaticContext.DeclareVariable(const Name: TLandrixXmlUtf8): Integer;
var
  I: Integer;
begin
  for I := 0 to Integer(Length(FVariables)) - 1 do
    if FVariables[I] = Name then
    begin
      Result := I;
      Exit;
    end;
  SetLength(FVariables, Length(FVariables) + 1);
  Result := Integer(High(FVariables));
  FVariables[Result] := Name;
end;

function SplitQName(const Name: TLandrixXmlUtf8; out Prefix, LocalName: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Prefix := '';
  LocalName := Name;
  for I := 1 to Length(Name) do
    if Name[I] = ':' then
    begin
      Prefix := Copy(Name, 1, I - 1);
      LocalName := Copy(Name, I + 1, MaxInt);
      Break;
    end;
  Result := Prefix <> '';
end;

function TLandrixXmlXPathStaticContext.FindVariable(const NamespaceUri, LocalName: TLandrixXmlUtf8): Integer;
var
  I: Integer;
  Prefix, Local, Uri: TLandrixXmlUtf8;
begin
  for I := 0 to Integer(Length(FVariables)) - 1 do
  begin
    SplitQName(FVariables[I], Prefix, Local);
    Uri := '';
    if Prefix <> '' then
      LookupNamespace(Prefix, Uri);
    if (Local = LocalName) and (Uri = NamespaceUri) then
    begin
      Result := I;
      Exit;
    end;
  end;
  Result := -1;
end;

function TLandrixXmlXPathStaticContext.DeclareFunction(const NamespaceUri, LocalName: TLandrixXmlUtf8;
  Arity: Integer): Integer;
begin
  Result := FindFunction(NamespaceUri, LocalName, Arity);
  if Result >= 0 then
    Exit;
  SetLength(FFunctions, Length(FFunctions) + 1);
  Result := Integer(High(FFunctions));
  FFunctions[Result].NamespaceUri := NamespaceUri;
  FFunctions[Result].LocalName := LocalName;
  FFunctions[Result].Arity := Arity;
end;

function TLandrixXmlXPathStaticContext.FindFunction(const NamespaceUri, LocalName: TLandrixXmlUtf8;
  Arity: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to Integer(Length(FFunctions)) - 1 do
    if (FFunctions[I].LocalName = LocalName) and (FFunctions[I].NamespaceUri = NamespaceUri) and
      (FFunctions[I].Arity = Arity) then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

function TLandrixXmlXPathStaticContext.GetVariableCount: Integer;
begin
  Result := Integer(Length(FVariables));
end;

function TLandrixXmlXPathStaticContext.GetFunctionCount: Integer;
begin
  Result := Integer(Length(FFunctions));
end;

{ --- lexer ------------------------------------------------------------- }

type
  TTokenKind = (tkEnd, tkName, tkString, tkInteger, tkDecimal, tkDouble, tkVariable, tkSymbol);

  TToken = record
    Kind: TTokenKind;
    { a name (also prefix:*, *:local and * as names), a symbol, the
      string value, the number text, a variable name without $ }
    Text: TLandrixXmlUtf8;
    Position: Integer;
  end;

  TParser = class
  private
    FSource: TLandrixXmlUtf8;
    FPos: Integer;
    FToken: TToken;
    FContext: TLandrixXmlXPathStaticContext;
    FOwnContext: Boolean;
    FNodes: TLandrixXmlXPathAstNodes;
    FCount: Integer;
    FSlotCount: Integer;
    { the for/some/every variables in scope: name and slot, innermost last }
    FLocalNames: TLandrixXmlUtf8Array;
    FLocalSlots: array of Integer;
    FLocalCount: Integer;
    procedure Error(const Msg: string; Position: Integer);
    procedure ErrorCode(const Code, Msg: string; Position: Integer);
    procedure SkipSpace;
    procedure Next;
    function PeekChar(Offset: Integer): AnsiChar;
    function IsSymbol(const S: TLandrixXmlUtf8): Boolean;
    function IsName(const S: TLandrixXmlUtf8): Boolean;
    procedure Expect(const S: TLandrixXmlUtf8);
    function NextIsSymbol(const S: TLandrixXmlUtf8): Boolean;
    function NewNode(Kind: TLandrixXmlXPathAstKind; Position: Integer): Integer;
    procedure AddChild(Parent, Child: Integer);
    procedure AddPredicate(Parent, Child: Integer);
    procedure ResolveName(const QName: TLandrixXmlUtf8; Position: Integer; DefaultFn: Boolean;
      out NamespaceUri, LocalName: TLandrixXmlUtf8);
    function ParseExpr: Integer;
    function ParseExprSingle: Integer;
    function ParseQuantified(Kind: TLandrixXmlXPathAstKind; const Keyword: TLandrixXmlUtf8): Integer;
    function ParseIf: Integer;
    function ParseOr: Integer;
    function ParseAnd: Integer;
    function ParseComparison: Integer;
    function ParseRange: Integer;
    function ParseAdditive: Integer;
    function ParseMultiplicative: Integer;
    function ParseUnion: Integer;
    function ParseIntersectExcept: Integer;
    function ParseCastable: Integer;
    function ParseCast: Integer;
    function ParseUnary: Integer;
    function ParsePath: Integer;
    function ParseRelativePath(Path: Integer): Integer;
    function ParseRelativeSteps(Path: Integer): Integer;
    function ParseStep: Integer;
    function ParseNodeTest(Step: Integer): Boolean;
    function ParsePrimary: Integer;
    function ParseFunctionCall(const AName: TLandrixXmlUtf8; Position: Integer): Integer;
    procedure ParsePredicates(Node: Integer);
    procedure ParseSingleType(Node: Integer);
    function ParseSequenceType: TLandrixXmlXPathSequenceType;
    procedure ParseKindTest(var T: TLandrixXmlXPathSequenceType);
    procedure ParseNameAndType(var T: TLandrixXmlXPathSequenceType; Element: Boolean);
    function DescendantStep(Position: Integer): Integer;
    function StartsStep: Boolean;
  public
    constructor Create(const Source: TLandrixXmlUtf8; Context: TLandrixXmlXPathStaticContext);
    destructor Destroy; override;
    function Parse: Integer;
  end;

{ XPath's normalize-space for the target of processing-instruction('x'),
  which has no inner spaces to keep: leading and trailing white space go. }
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

{ True if S is an NCName (the target of processing-instruction('...')),
  with the name characters of XML 1.0 fifth edition as the reader. }
function IsNCName(const S: TLandrixXmlUtf8): Boolean;
begin
  Result := (S <> '') and (Pos(':', LandrixXmlUtf8ToString(S)) = 0) and
    (LandrixXmlCheckName(PAnsiChar(S), Integer(Length(S))) = -1);
end;

function IsNameStart(C: AnsiChar): Boolean;
begin
  Result := (C in ['A'..'Z', 'a'..'z', '_']) or (Ord(C) >= $80);
end;

function IsNameChar(C: AnsiChar): Boolean;
begin
  Result := IsNameStart(C) or (C in ['0'..'9', '-', '.']);
end;

constructor TParser.Create(const Source: TLandrixXmlUtf8; Context: TLandrixXmlXPathStaticContext);
begin
  inherited Create;
  FSource := Source;
  FPos := 1;
  if Context = nil then
  begin
    FContext := TLandrixXmlXPathStaticContext.Create;
    FOwnContext := True;
  end
  else
    FContext := Context;
  FSlotCount := FContext.VariableCount;
end;

destructor TParser.Destroy;
begin
  if FOwnContext then
    FContext.Free;
  inherited Destroy;
end;

procedure TParser.ErrorCode(const Code, Msg: string; Position: Integer);
begin
  raise ELandrixXmlXPathError.CreateXPath(Code, Msg + ' at offset ' + IntToStr(Position - 1) + ' in "' +
    LandrixXmlEscapeForMessage(FSource, 200) + '"');
end;

procedure TParser.Error(const Msg: string; Position: Integer);
begin
  ErrorCode('XPST0003', Msg, Position);
end;

function TParser.PeekChar(Offset: Integer): AnsiChar;
begin
  if FPos + Offset <= Length(FSource) then
    Result := AnsiChar(FSource[FPos + Offset])
  else
    Result := #0;
end;

procedure TParser.SkipSpace;
var
  Depth: Integer;
begin
  while FPos <= Length(FSource) do
  begin
    if FSource[FPos] in [' ', #9, #10, #13] then
      Inc(FPos)
    else if (FSource[FPos] = '(') and (PeekChar(1) = ':') then
    begin
      { a comment, maybe nested }
      Depth := 0;
      repeat
        if (FSource[FPos] = '(') and (PeekChar(1) = ':') then
        begin
          Inc(Depth);
          Inc(FPos, 2);
        end
        else if (FSource[FPos] = ':') and (PeekChar(1) = ')') then
        begin
          Dec(Depth);
          Inc(FPos, 2);
        end
        else
          Inc(FPos);
      until (Depth = 0) or (FPos > Length(FSource));
      if Depth > 0 then
        Error('unterminated comment', FPos);
    end
    else
      Break;
  end;
end;

procedure TParser.Next;
var
  Start: Integer;
  Quote: AnsiChar;
  S: TLandrixXmlUtf8;
  HasDot: Boolean;

  procedure ReadName;
  begin
    while (FPos <= Length(FSource)) and IsNameChar(AnsiChar(FSource[FPos])) do
      Inc(FPos);
  end;

  procedure Symbol(Len: Integer);
  begin
    FToken.Kind := tkSymbol;
    FToken.Text := Copy(FSource, FPos, Len);
    Inc(FPos, Len);
  end;

begin
  SkipSpace;
  FToken.Position := FPos;
  FToken.Text := '';
  if FPos > Length(FSource) then
  begin
    FToken.Kind := tkEnd;
    Exit;
  end;
  Start := FPos;
  case FSource[FPos] of
    '''', '"':
      begin
        Quote := AnsiChar(FSource[FPos]);
        Inc(FPos);
        S := '';
        while True do
        begin
          if FPos > Length(FSource) then
            Error('unterminated string literal', Start);
          if AnsiChar(FSource[FPos]) = Quote then
          begin
            if PeekChar(1) = Quote then
            begin
              S := S + Copy(FSource, FPos, 1);
              Inc(FPos, 2);
              Continue;
            end;
            Inc(FPos);
            Break;
          end;
          S := S + Copy(FSource, FPos, 1);
          Inc(FPos);
        end;
        FToken.Kind := tkString;
        FToken.Text := S;
      end;
    '0'..'9':
      begin
        HasDot := False;
        while (FPos <= Length(FSource)) and (FSource[FPos] in ['0'..'9']) do
          Inc(FPos);
        if (FPos <= Length(FSource)) and (FSource[FPos] = '.') and (PeekChar(1) <> '.') then
        begin
          HasDot := True;
          Inc(FPos);
          while (FPos <= Length(FSource)) and (FSource[FPos] in ['0'..'9']) do
            Inc(FPos);
        end;
        FToken.Kind := tkInteger;
        if HasDot then
          FToken.Kind := tkDecimal;
        if (FPos <= Length(FSource)) and (FSource[FPos] in ['e', 'E']) then
        begin
          Inc(FPos);
          if (FPos <= Length(FSource)) and (FSource[FPos] in ['+', '-']) then
            Inc(FPos);
          if (FPos > Length(FSource)) or not (FSource[FPos] in ['0'..'9']) then
            Error('invalid number', Start);
          while (FPos <= Length(FSource)) and (FSource[FPos] in ['0'..'9']) do
            Inc(FPos);
          FToken.Kind := tkDouble;
        end;
        if (FPos <= Length(FSource)) and IsNameStart(AnsiChar(FSource[FPos])) then
          Error('a number must not be followed by a name', Start);
        FToken.Text := Copy(FSource, Start, FPos - Start);
      end;
    '.':
      if PeekChar(1) in ['0'..'9'] then
      begin
        { .5 }
        Inc(FPos);
        while (FPos <= Length(FSource)) and (FSource[FPos] in ['0'..'9']) do
          Inc(FPos);
        FToken.Kind := tkDecimal;
        if (FPos <= Length(FSource)) and (FSource[FPos] in ['e', 'E']) then
        begin
          Inc(FPos);
          if (FPos <= Length(FSource)) and (FSource[FPos] in ['+', '-']) then
            Inc(FPos);
          if (FPos > Length(FSource)) or not (FSource[FPos] in ['0'..'9']) then
            Error('invalid number', Start);
          while (FPos <= Length(FSource)) and (FSource[FPos] in ['0'..'9']) do
            Inc(FPos);
          FToken.Kind := tkDouble;
        end;
        FToken.Text := Copy(FSource, Start, FPos - Start);
      end
      else if PeekChar(1) = '.' then
        Symbol(2)
      else
        Symbol(1);
    '$':
      begin
        Inc(FPos);
        SkipSpace;
        if (FPos > Length(FSource)) or not IsNameStart(AnsiChar(FSource[FPos])) then
          Error('a variable name was expected', Start);
        Start := FPos;
        ReadName;
        if (FPos < Length(FSource)) and (FSource[FPos] = ':') and IsNameStart(PeekChar(1)) then
        begin
          Inc(FPos);
          ReadName;
        end;
        FToken.Kind := tkVariable;
        FToken.Text := Copy(FSource, Start, FPos - Start);
      end;
    '*':
      if (PeekChar(1) = ':') and IsNameStart(PeekChar(2)) then
      begin
        { *:local }
        Inc(FPos, 2);
        ReadName;
        FToken.Kind := tkName;
        FToken.Text := Copy(FSource, Start, FPos - Start);
      end
      else
      begin
        FToken.Kind := tkName;
        FToken.Text := '*';
        Inc(FPos);
      end;
    '/':
      if PeekChar(1) = '/' then
        Symbol(2)
      else
        Symbol(1);
    '!':
      if PeekChar(1) = '=' then
        Symbol(2)
      else
        Error('unexpected character "!"', Start);
    '<', '>':
      if (PeekChar(1) = '=') or (PeekChar(1) = FSource[FPos]) then
        Symbol(2)
      else
        Symbol(1);
    ':':
      if PeekChar(1) = ':' then
        Symbol(2)
      else
        Error('unexpected character ":"', Start);
    '(', ')', '[', ']', ',', '@', '=', '+', '-', '|', '?':
      Symbol(1);
  else
    if IsNameStart(AnsiChar(FSource[FPos])) then
    begin
      ReadName;
      if (FPos < Length(FSource)) and (FSource[FPos] = ':') then
      begin
        if IsNameStart(PeekChar(1)) then
        begin
          Inc(FPos);
          ReadName;
        end
        else if PeekChar(1) = '*' then
          Inc(FPos, 2);
      end;
      FToken.Kind := tkName;
      FToken.Text := Copy(FSource, Start, FPos - Start);
    end
    else
      Error('unexpected character', Start);
  end;
end;

function TParser.IsSymbol(const S: TLandrixXmlUtf8): Boolean;
begin
  Result := (FToken.Kind = tkSymbol) and (FToken.Text = S);
end;

function TParser.IsName(const S: TLandrixXmlUtf8): Boolean;
begin
  Result := (FToken.Kind = tkName) and (FToken.Text = S);
end;

procedure TParser.Expect(const S: TLandrixXmlUtf8);
begin
  if not IsSymbol(S) then
    Error('"' + LandrixXmlUtf8ToString(S) + '" was expected', FToken.Position);
  Next;
end;

{ True if the next non-space character after the current token starts S. }
function TParser.NextIsSymbol(const S: TLandrixXmlUtf8): Boolean;
var
  Saved: Integer;
begin
  Saved := FPos;
  SkipSpace;
  Result := Copy(FSource, FPos, Length(S)) = S;
  FPos := Saved;
end;

function TParser.NewNode(Kind: TLandrixXmlXPathAstKind; Position: Integer): Integer;
begin
  if FCount = Length(FNodes) then
    SetLength(FNodes, 2 * FCount + 16);
  Result := FCount;
  FNodes[Result].Kind := Kind;
  FNodes[Result].Op := 0;
  FNodes[Result].Children := nil;
  FNodes[Result].Predicates := nil;
  FNodes[Result].Slots := nil;
  FNodes[Result].Slot := -1;
  FNodes[Result].Axis := xaxChild;
  FNodes[Result].NodeTest := xntAnyNode;
  FNodes[Result].NamespaceUri := '';
  FNodes[Result].LocalName := '';
  FNodes[Result].RootStart := False;
  FNodes[Result].Text := '';
  FNodes[Result].Decimal := LandrixXmlDecimalZero;
  FNodes[Result].DoubleValue := LandrixXmlDoubleZero(False);
  FNodes[Result].AtomicType := xikNone;
  FNodes[Result].AllowEmpty := False;
  FNodes[Result].Position := Position;
  Inc(FCount);
end;

procedure TParser.AddChild(Parent, Child: Integer);
begin
  SetLength(FNodes[Parent].Children, Length(FNodes[Parent].Children) + 1);
  FNodes[Parent].Children[High(FNodes[Parent].Children)] := Child;
end;

procedure TParser.AddPredicate(Parent, Child: Integer);
begin
  SetLength(FNodes[Parent].Predicates, Length(FNodes[Parent].Predicates) + 1);
  FNodes[Parent].Predicates[High(FNodes[Parent].Predicates)] := Child;
end;

procedure TParser.ResolveName(const QName: TLandrixXmlUtf8; Position: Integer; DefaultFn: Boolean;
  out NamespaceUri, LocalName: TLandrixXmlUtf8);
var
  Prefix: TLandrixXmlUtf8;
begin
  if SplitQName(QName, Prefix, LocalName) then
  begin
    if not FContext.LookupNamespace(Prefix, NamespaceUri) then
      ErrorCode('XPST0081', 'the prefix "' + LandrixXmlUtf8ToString(Prefix) + '" is not declared', Position);
  end
  else if DefaultFn then
    NamespaceUri := LandrixXmlXPathFunctionNamespace
  else
    NamespaceUri := '';
end;

function TParser.Parse: Integer;
begin
  Next;
  Result := ParseExpr;
  if FToken.Kind <> tkEnd then
    Error('unexpected "' + LandrixXmlUtf8ToString(FToken.Text) + '"', FToken.Position);
end;

function TParser.ParseExpr: Integer;
var
  First, Seq: Integer;
begin
  First := ParseExprSingle;
  if not IsSymbol(',') then
  begin
    Result := First;
    Exit;
  end;
  Seq := NewNode(xakSequence, FNodes[First].Position);
  AddChild(Seq, First);
  while IsSymbol(',') do
  begin
    Next;
    AddChild(Seq, ParseExprSingle);
  end;
  Result := Seq;
end;

function TParser.ParseExprSingle: Integer;
begin
  if (FToken.Kind = tkName) and NextIsSymbol('$') then
  begin
    if FToken.Text = 'for' then
    begin
      Result := ParseQuantified(xakFor, 'return');
      Exit;
    end;
    if FToken.Text = 'some' then
    begin
      Result := ParseQuantified(xakSome, 'satisfies');
      Exit;
    end;
    if FToken.Text = 'every' then
    begin
      Result := ParseQuantified(xakEvery, 'satisfies');
      Exit;
    end;
  end;
  if IsName('if') and NextIsSymbol('(') then
  begin
    Result := ParseIf;
    Exit;
  end;
  Result := ParseOr;
end;

{ for/some/every $a in E (, $b in E)* return|satisfies E }
function TParser.ParseQuantified(Kind: TLandrixXmlXPathAstKind; const Keyword: TLandrixXmlUtf8): Integer;
var
  SavedLocals: Integer;
  Name, Uri, Local: TLandrixXmlUtf8;
  Slot: Integer;
begin
  Result := NewNode(Kind, FToken.Position);
  SavedLocals := FLocalCount;
  Next;
  repeat
    if FToken.Kind <> tkVariable then
      Error('a variable was expected', FToken.Position);
    Name := FToken.Text;
    ResolveName(Name, FToken.Position, False, Uri, Local);
    Next;
    if not IsName('in') then
      Error('"in" was expected', FToken.Position);
    Next;
    { the binding expression does not see its own variable }
    AddChild(Result, ParseExprSingle);
    Slot := FSlotCount;
    Inc(FSlotCount);
    SetLength(FNodes[Result].Slots, Length(FNodes[Result].Slots) + 1);
    FNodes[Result].Slots[High(FNodes[Result].Slots)] := Slot;
    if FLocalCount = Length(FLocalNames) then
    begin
      SetLength(FLocalNames, 2 * FLocalCount + 4);
      SetLength(FLocalSlots, 2 * FLocalCount + 4);
    end;
    FLocalNames[FLocalCount] := Uri + #0 + Local;
    FLocalSlots[FLocalCount] := Slot;
    Inc(FLocalCount);
    if not IsSymbol(',') then
      Break;
    Next;
  until False;
  if not IsName(Keyword) then
    Error('"' + LandrixXmlUtf8ToString(Keyword) + '" was expected', FToken.Position);
  Next;
  AddChild(Result, ParseExprSingle);
  FLocalCount := SavedLocals;
end;

function TParser.ParseIf: Integer;
begin
  Result := NewNode(xakIf, FToken.Position);
  Next;
  Expect('(');
  AddChild(Result, ParseExpr);
  Expect(')');
  if not IsName('then') then
    Error('"then" was expected', FToken.Position);
  Next;
  AddChild(Result, ParseExprSingle);
  if not IsName('else') then
    Error('"else" was expected', FToken.Position);
  Next;
  AddChild(Result, ParseExprSingle);
end;

function TParser.ParseOr: Integer;
var
  N: Integer;
begin
  Result := ParseAnd;
  while IsName('or') do
  begin
    N := NewNode(xakOr, FToken.Position);
    Next;
    AddChild(N, Result);
    AddChild(N, ParseAnd);
    Result := N;
  end;
end;

function TParser.ParseAnd: Integer;
var
  N: Integer;
begin
  Result := ParseComparison;
  while IsName('and') do
  begin
    N := NewNode(xakAnd, FToken.Position);
    Next;
    AddChild(N, Result);
    AddChild(N, ParseComparison);
    Result := N;
  end;
end;

function TParser.ParseComparison: Integer;
var
  N: Integer;
  Kind: TLandrixXmlXPathAstKind;
  Op: TLandrixXmlXPathCompare;
begin
  Result := ParseRange;
  Kind := xakGeneralCompare;
  if FToken.Kind = tkSymbol then
  begin
    if FToken.Text = '=' then
      Op := xpcEq
    else if FToken.Text = '!=' then
      Op := xpcNe
    else if FToken.Text = '<' then
      Op := xpcLt
    else if FToken.Text = '<=' then
      Op := xpcLe
    else if FToken.Text = '>' then
      Op := xpcGt
    else if FToken.Text = '>=' then
      Op := xpcGe
    else if FToken.Text = '<<' then
    begin
      Kind := xakNodeCompare;
      Op := xpcLt;
    end
    else if FToken.Text = '>>' then
    begin
      Kind := xakNodeCompare;
      Op := xpcGt;
    end
    else
      Exit;
  end
  else if FToken.Kind = tkName then
  begin
    Kind := xakValueCompare;
    if FToken.Text = 'eq' then
      Op := xpcEq
    else if FToken.Text = 'ne' then
      Op := xpcNe
    else if FToken.Text = 'lt' then
      Op := xpcLt
    else if FToken.Text = 'le' then
      Op := xpcLe
    else if FToken.Text = 'gt' then
      Op := xpcGt
    else if FToken.Text = 'ge' then
      Op := xpcGe
    else if FToken.Text = 'is' then
    begin
      Kind := xakNodeCompare;
      Op := xpcEq;
    end
    else
      Exit;
  end
  else
    Exit;
  N := NewNode(Kind, FToken.Position);
  FNodes[N].Op := Ord(Op);
  Next;
  AddChild(N, Result);
  AddChild(N, ParseRange);
  Result := N;
end;

function TParser.ParseRange: Integer;
var
  N: Integer;
begin
  Result := ParseAdditive;
  if IsName('to') then
  begin
    N := NewNode(xakRange, FToken.Position);
    Next;
    AddChild(N, Result);
    AddChild(N, ParseAdditive);
    Result := N;
  end;
end;

function TParser.ParseAdditive: Integer;
var
  N: Integer;
begin
  Result := ParseMultiplicative;
  while IsSymbol('+') or IsSymbol('-') do
  begin
    N := NewNode(xakArithmetic, FToken.Position);
    if FToken.Text = '+' then
      FNodes[N].Op := Ord(xpaAdd)
    else
      FNodes[N].Op := Ord(xpaSubtract);
    Next;
    AddChild(N, Result);
    AddChild(N, ParseMultiplicative);
    Result := N;
  end;
end;

{ True and Op if the current token is *, div, idiv or mod. }
function MultiplicativeOp(const Token: TToken; out Op: TLandrixXmlXPathArithmetic): Boolean;
begin
  Result := True;
  Op := xpaMultiply;
  if Token.Kind <> tkName then
    Result := False
  else if Token.Text = 'div' then
    Op := xpaDivide
  else if Token.Text = 'idiv' then
    Op := xpaIntegerDivide
  else if Token.Text = 'mod' then
    Op := xpaModulo
  else if Token.Text <> '*' then
    Result := False;
end;

function TParser.ParseMultiplicative: Integer;
var
  N: Integer;
  Op: TLandrixXmlXPathArithmetic;
begin
  Result := ParseUnion;
  while MultiplicativeOp(FToken, Op) do
  begin
    N := NewNode(xakArithmetic, FToken.Position);
    FNodes[N].Op := Ord(Op);
    Next;
    AddChild(N, Result);
    AddChild(N, ParseUnion);
    Result := N;
  end;
end;

function TParser.ParseUnion: Integer;
var
  N: Integer;
begin
  Result := ParseIntersectExcept;
  while IsSymbol('|') or IsName('union') do
  begin
    N := NewNode(xakUnion, FToken.Position);
    Next;
    AddChild(N, Result);
    AddChild(N, ParseIntersectExcept);
    Result := N;
  end;
end;

function TParser.ParseIntersectExcept: Integer;
var
  N: Integer;

  function Operand: Integer;
  begin
    Result := ParseCastable;
    if IsName('instance') or IsName('treat') then
      Error('"' + LandrixXmlUtf8ToString(FToken.Text) + '" is not supported', FToken.Position);
  end;

begin
  Result := Operand;
  while IsName('intersect') or IsName('except') do
  begin
    N := NewNode(xakIntersectExcept, FToken.Position);
    FNodes[N].Op := Ord(IsName('except'));
    Next;
    AddChild(N, Result);
    AddChild(N, Operand);
    Result := N;
  end;
end;

function TParser.ParseCastable: Integer;
var
  N: Integer;
begin
  Result := ParseCast;
  if IsName('castable') then
  begin
    N := NewNode(xakCastable, FToken.Position);
    Next;
    if not IsName('as') then
      Error('"as" was expected', FToken.Position);
    Next;
    AddChild(N, Result);
    ParseSingleType(N);
    Result := N;
  end;
end;

function TParser.ParseCast: Integer;
var
  N: Integer;
begin
  Result := ParseUnary;
  if IsName('cast') then
  begin
    N := NewNode(xakCast, FToken.Position);
    Next;
    if not IsName('as') then
      Error('"as" was expected', FToken.Position);
    Next;
    AddChild(N, Result);
    ParseSingleType(N);
    Result := N;
  end;
end;

procedure TParser.ParseSingleType(Node: Integer);
var
  Uri, Local: TLandrixXmlUtf8;
begin
  if FToken.Kind <> tkName then
    Error('a type name was expected', FToken.Position);
  ResolveName(FToken.Text, FToken.Position, False, Uri, Local);
  if Uri <> LandrixXmlXPathSchemaNamespace then
    ErrorCode('XPST0051', 'unknown atomic type "' + LandrixXmlUtf8ToString(FToken.Text) + '"', FToken.Position);
  FNodes[Node].AtomicType := LandrixXmlXPathAtomicTypeByName(Local);
  if (FNodes[Node].AtomicType = xikAnyAtomic) or (Local = 'NOTATION') then
    ErrorCode('XPST0080', 'cannot cast to "' + LandrixXmlUtf8ToString(FToken.Text) + '"', FToken.Position);
  if FNodes[Node].AtomicType = xikNone then
    ErrorCode('XPST0051', 'the type "' + LandrixXmlUtf8ToString(FToken.Text) + '" is not supported here',
      FToken.Position);
  Next;
  if IsSymbol('?') then
  begin
    FNodes[Node].AllowEmpty := True;
    Next;
  end;
end;

procedure InitSequenceType(out T: TLandrixXmlXPathSequenceType);
begin
  T.Kind := xtkAnyItem;
  T.AtomicType := xikNone;
  T.KindTest := xktAnyNode;
  T.NamespaceUri := '';
  T.LocalName := '';
  T.ContentType := '';
  T.Nilled := False;
  T.ElementTest := False;
  T.Occurrence := xocOne;
  T.Declared := True;
end;

const
  { the built-in types of XML Schema 1.0 and XPath 2.0 }
  TypeNames: array[0..50] of string = (
    'anyType', 'anySimpleType', 'anyAtomicType', 'untyped', 'untypedAtomic', 'string', 'boolean', 'decimal',
    'float', 'double', 'duration', 'dayTimeDuration', 'yearMonthDuration', 'dateTime', 'time', 'date',
    'gYearMonth', 'gYear', 'gMonthDay', 'gDay', 'gMonth', 'hexBinary', 'base64Binary', 'anyURI', 'QName',
    'NOTATION', 'normalizedString', 'token', 'language', 'NMTOKEN', 'NMTOKENS', 'Name', 'NCName', 'ID',
    'IDREF', 'IDREFS', 'ENTITY', 'ENTITIES', 'integer', 'nonPositiveInteger', 'negativeInteger', 'long',
    'int', 'short', 'byte', 'nonNegativeInteger', 'unsignedLong', 'unsignedInt', 'unsignedShort',
    'unsignedByte', 'positiveInteger');

{ The type names of element(N, T) and attribute(N, T). }
function KnownTypeName(const LocalName: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  for I := Low(TypeNames) to High(TypeNames) do
    if LandrixXmlStringToUtf8(TypeNames[I]) = LocalName then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

{ SequenceType: empty-sequence(), or an item type with an optional
  occurrence indicator. }
function TParser.ParseSequenceType: TLandrixXmlXPathSequenceType;
var
  Name, Uri, Local: TLandrixXmlUtf8;
  Position: Integer;
begin
  InitSequenceType(Result);
  if FToken.Kind <> tkName then
    Error('a sequence type was expected', FToken.Position);
  Name := FToken.Text;
  Position := FToken.Position;
  if NextIsSymbol('(') then
  begin
    if Name = 'empty-sequence' then
    begin
      Next;
      Expect('(');
      Expect(')');
      { no occurrence indicator: matches the empty sequence only }
      Result.Kind := xtkEmpty;
      Result.Occurrence := xocOptional;
      Exit;
    end;
    if Name = 'item' then
    begin
      Next;
      Expect('(');
      Expect(')');
    end
    else
    begin
      Result.Kind := xtkNode;
      ParseKindTest(Result);
    end;
  end
  else
  begin
    if Pos('*', LandrixXmlUtf8ToString(Name)) > 0 then
      Error('an atomic type name was expected', Position);
    ResolveName(Name, Position, False, Uri, Local);
    if Uri <> LandrixXmlXPathSchemaNamespace then
      ErrorCode('XPST0051', 'unknown atomic type "' + LandrixXmlUtf8ToString(Name) + '"', Position);
    Result.Kind := xtkAtomic;
    Result.AtomicType := LandrixXmlXPathAtomicTypeByName(Local);
    { xs:float: no float values yet }
    if Result.AtomicType in [xikNone, xikFloat] then
      ErrorCode('XPST0051', 'the type "' + LandrixXmlUtf8ToString(Name) + '" is not supported here', Position);
    Next;
  end;
  if IsSymbol('?') then
    Result.Occurrence := xocOptional
  else if IsName('*') then
    Result.Occurrence := xocMany
  else if IsSymbol('+') then
    Result.Occurrence := xocOneOrMore
  else
    Exit;
  Next;
end;

{ A kind test at the current token (its name; "(" follows). }
procedure TParser.ParseKindTest(var T: TLandrixXmlXPathSequenceType);
var
  Name: TLandrixXmlUtf8;
  Position: Integer;
begin
  Name := FToken.Text;
  Position := FToken.Position;
  if Name = 'node' then
    T.KindTest := xktAnyNode
  else if Name = 'document-node' then
    T.KindTest := xktDocument
  else if Name = 'element' then
    T.KindTest := xktElement
  else if Name = 'attribute' then
    T.KindTest := xktAttribute
  else if Name = 'text' then
    T.KindTest := xktText
  else if Name = 'comment' then
    T.KindTest := xktComment
  else if Name = 'processing-instruction' then
    T.KindTest := xktProcessingInstruction
  else if (Name = 'schema-element') or (Name = 'schema-attribute') then
    ErrorCode('XPST0008', '"' + LandrixXmlUtf8ToString(Name) + '()" needs a schema, none is in scope', Position)
  else
    Error('unknown item type "' + LandrixXmlUtf8ToString(Name) + '()"', Position);
  Next;
  Expect('(');
  case T.KindTest of
    xktProcessingInstruction:
      if (FToken.Kind = tkName) or (FToken.Kind = tkString) then
      begin
        if (FToken.Kind = tkName) and ((Pos(':', LandrixXmlUtf8ToString(FToken.Text)) > 0) or (FToken.Text = '*')) then
          Error('the target of processing-instruction() must be a name without prefix', FToken.Position);
        if (FToken.Kind = tkString) and not IsNCName(Trimmed(FToken.Text)) then
          ErrorCode('XPTY0004', 'the target of processing-instruction() is not a name', FToken.Position);
        T.LocalName := Trimmed(FToken.Text);
        Next;
      end;
    xktDocument:
      if IsName('element') then
      begin
        T.ElementTest := True;
        Next;
        Expect('(');
        ParseNameAndType(T, True);
        Expect(')');
      end
      else if IsName('schema-element') then
        ErrorCode('XPST0008', '"schema-element()" needs a schema, none is in scope', FToken.Position);
    xktElement:
      ParseNameAndType(T, True);
    xktAttribute:
      ParseNameAndType(T, False);
  else
    { node(), text(), comment() }
  end;
  Expect(')');
end;

{ The arguments of element() and attribute(): nothing, a name or *, and
  optionally a type name (with "?" for elements). }
procedure TParser.ParseNameAndType(var T: TLandrixXmlXPathSequenceType; Element: Boolean);
var
  Uri, Local: TLandrixXmlUtf8;
begin
  if IsSymbol(')') then
    Exit;
  if FToken.Kind <> tkName then
    Error('a name or "*" was expected', FToken.Position);
  if FToken.Text <> '*' then
  begin
    if Pos('*', LandrixXmlUtf8ToString(FToken.Text)) > 0 then
      Error('a name or "*" was expected', FToken.Position);
    ResolveName(FToken.Text, FToken.Position, False, T.NamespaceUri, T.LocalName);
  end;
  Next;
  if not IsSymbol(',') then
    Exit;
  Next;
  if (FToken.Kind <> tkName) or (Pos('*', LandrixXmlUtf8ToString(FToken.Text)) > 0) then
    Error('a type name was expected', FToken.Position);
  ResolveName(FToken.Text, FToken.Position, False, Uri, Local);
  if (Uri <> LandrixXmlXPathSchemaNamespace) or not KnownTypeName(Local) then
    ErrorCode('XPST0008', 'unknown type "' + LandrixXmlUtf8ToString(FToken.Text) + '"', FToken.Position);
  T.ContentType := Local;
  Next;
  if Element and IsSymbol('?') then
  begin
    T.Nilled := True;
    Next;
  end;
end;

function TParser.ParseUnary: Integer;
var
  N: Integer;
begin
  if IsSymbol('-') then
  begin
    N := NewNode(xakNegate, FToken.Position);
    Next;
    AddChild(N, ParseUnary);
    Result := N;
  end
  else if IsSymbol('+') then
  begin
    N := NewNode(xakUnaryPlus, FToken.Position);
    Next;
    AddChild(N, ParseUnary);
    Result := N;
  end
  else
    Result := ParsePath;
end;

{ descendant-or-self::node(), what "//" stands for }
function TParser.DescendantStep(Position: Integer): Integer;
begin
  Result := NewNode(xakStep, Position);
  FNodes[Result].Axis := xaxDescendantOrSelf;
  FNodes[Result].NodeTest := xntAnyNode;
end;

{ True if the current token can begin a step of a relative path. }
function TParser.StartsStep: Boolean;
begin
  case FToken.Kind of
    tkName, tkString, tkInteger, tkDecimal, tkDouble, tkVariable:
      Result := True;
    tkSymbol:
      Result := IsSymbol('@') or IsSymbol('.') or IsSymbol('..') or IsSymbol('(');
  else
    Result := False;
  end;
end;

function TParser.ParsePath: Integer;
var
  Path, First: Integer;
begin
  if IsSymbol('/') then
  begin
    Path := NewNode(xakPath, FToken.Position);
    FNodes[Path].RootStart := True;
    Next;
    { "/" alone, or followed by a relative path (anything that can start
      one belongs to it, as the XPath grammar note on a leading "/" says) }
    if not StartsStep then
    begin
      FNodes[Path].Kind := xakRoot;
      Result := Path;
      Exit;
    end;
    Result := ParseRelativePath(Path);
    Exit;
  end;
  if IsSymbol('//') then
  begin
    Path := NewNode(xakPath, FToken.Position);
    FNodes[Path].RootStart := True;
    AddChild(Path, DescendantStep(FToken.Position));
    Next;
    Result := ParseRelativePath(Path);
    Exit;
  end;
  { a relative path: a single step stays as it is }
  First := ParseStep;
  if not IsSymbol('/') and not IsSymbol('//') then
  begin
    Result := First;
    Exit;
  end;
  Path := NewNode(xakPath, FNodes[First].Position);
  AddChild(Path, First);
  Result := ParseRelativeSteps(Path);
end;

function TParser.ParseRelativePath(Path: Integer): Integer;
begin
  AddChild(Path, ParseStep);
  Result := ParseRelativeSteps(Path);
end;

{ the steps after the first one: ("/" | "//") step ... }
function TParser.ParseRelativeSteps(Path: Integer): Integer;
begin
  while IsSymbol('/') or IsSymbol('//') do
  begin
    if IsSymbol('//') then
      AddChild(Path, DescendantStep(FToken.Position));
    Next;
    AddChild(Path, ParseStep);
  end;
  Result := Path;
end;

const
  AxisNames: array[TLandrixXmlXPathAxis] of string = ('child', 'descendant', 'attribute', 'self',
    'descendant-or-self', 'following-sibling', 'parent', 'ancestor', 'preceding-sibling', 'preceding',
    'ancestor-or-self', 'following');

function TParser.ParseStep: Integer;
var
  Step: Integer;
  A: TLandrixXmlXPathAxis;
  Found: Boolean;
begin
  if IsSymbol('..') then
  begin
    Step := NewNode(xakStep, FToken.Position);
    FNodes[Step].Axis := xaxParent;
    FNodes[Step].NodeTest := xntAnyNode;
    Next;
    ParsePredicates(Step);
    Result := Step;
    Exit;
  end;
  if IsSymbol('@') then
  begin
    Step := NewNode(xakStep, FToken.Position);
    FNodes[Step].Axis := xaxAttribute;
    Next;
    if not ParseNodeTest(Step) then
      Error('a node test was expected', FToken.Position);
    ParsePredicates(Step);
    Result := Step;
    Exit;
  end;
  if (FToken.Kind = tkName) and NextIsSymbol('::') then
  begin
    Step := NewNode(xakStep, FToken.Position);
    Found := False;
    for A := Low(TLandrixXmlXPathAxis) to High(TLandrixXmlXPathAxis) do
      if FToken.Text = LandrixXmlStringToUtf8(AxisNames[A]) then
      begin
        FNodes[Step].Axis := A;
        Found := True;
      end;
    if not Found then
    begin
      if FToken.Text = 'namespace' then
        Error('the axis "' + LandrixXmlUtf8ToString(FToken.Text) + '" is not supported', FToken.Position);
      Error('unknown axis "' + LandrixXmlUtf8ToString(FToken.Text) + '"', FToken.Position);
    end;
    Next;
    Expect('::');
    if not ParseNodeTest(Step) then
      Error('a node test was expected', FToken.Position);
    ParsePredicates(Step);
    Result := Step;
    Exit;
  end;
  { a name test or kind test on the child axis, else a filter expression }
  if FToken.Kind = tkName then
  begin
    Step := NewNode(xakStep, FToken.Position);
    FNodes[Step].Axis := xaxChild;
    if ParseNodeTest(Step) then
    begin
      ParsePredicates(Step);
      Result := Step;
      Exit;
    end;
    { not a node test: drop the node again }
    Dec(FCount);
  end;
  Result := ParsePrimary;
  if IsSymbol('[') then
  begin
    Step := NewNode(xakFilter, FNodes[Result].Position);
    AddChild(Step, Result);
    ParsePredicates(Step);
    Result := Step;
  end;
end;

{ A name test or kind test at the current token; False (nothing consumed)
  if the token is a function call instead. }
function TParser.ParseNodeTest(Step: Integer): Boolean;
var
  Name, Prefix, Local, Uri: TLandrixXmlUtf8;
  Position: Integer;
begin
  Result := False;
  if FToken.Kind <> tkName then
    Exit;
  Name := FToken.Text;
  Position := FToken.Position;
  if NextIsSymbol('(') then
  begin
    { kind tests }
    if Name = 'node' then
      FNodes[Step].NodeTest := xntAnyNode
    else if Name = 'text' then
      FNodes[Step].NodeTest := xntText
    else if Name = 'comment' then
      FNodes[Step].NodeTest := xntComment
    else if Name = 'processing-instruction' then
      FNodes[Step].NodeTest := xntProcessingInstruction
    else if Name = 'document-node' then
      FNodes[Step].NodeTest := xntDocumentNode
    else if (Name = 'element') or (Name = 'attribute') then
      FNodes[Step].NodeTest := xntAnyElement
    else if (Name = 'schema-element') or (Name = 'schema-attribute') then
      Error('"' + LandrixXmlUtf8ToString(Name) + '()" is not supported', Position)
    else
      Exit;
    Next;
    Expect('(');
    if (FNodes[Step].NodeTest = xntDocumentNode) and not IsSymbol(')') then
      Error('"document-node()" with an argument is not supported', Position);
    if FNodes[Step].NodeTest = xntProcessingInstruction then
    begin
      if (FToken.Kind = tkName) or (FToken.Kind = tkString) then
      begin
        if (FToken.Kind = tkName) and ((Pos(':', LandrixXmlUtf8ToString(FToken.Text)) > 0) or (FToken.Text = '*')) then
          Error('the target of processing-instruction() must be a name without prefix', FToken.Position);
        if (FToken.Kind = tkString) and not IsNCName(Trimmed(FToken.Text)) then
          ErrorCode('XPTY0004', 'the target of processing-instruction() is not a name', FToken.Position);
        FNodes[Step].LocalName := Trimmed(FToken.Text);
        Next;
      end;
    end
    else if FNodes[Step].NodeTest = xntAnyElement then
    begin
      { element() and attribute(), also with "*"; no names or types }
      if IsName('*') then
        Next;
      if not IsSymbol(')') then
        Error('"' + LandrixXmlUtf8ToString(Name) + '()" with a name or type is not supported', Position);
      if Name = 'attribute' then
        FNodes[Step].NodeTest := xntAnyAttribute;
    end;
    Expect(')');
    Result := True;
    Exit;
  end;
  if Name = '*' then
    FNodes[Step].NodeTest := xntAnyName
  else if Copy(Name, 1, 2) = '*:' then
  begin
    FNodes[Step].NodeTest := xntLocalWildcard;
    FNodes[Step].LocalName := Copy(Name, 3, MaxInt);
  end
  else if (Length(Name) > 2) and (Copy(Name, Length(Name) - 1, 2) = ':*') then
  begin
    Prefix := Copy(Name, 1, Length(Name) - 2);
    if not FContext.LookupNamespace(Prefix, Uri) then
      ErrorCode('XPST0081', 'the prefix "' + LandrixXmlUtf8ToString(Prefix) + '" is not declared', Position);
    FNodes[Step].NodeTest := xntNamespaceWildcard;
    FNodes[Step].NamespaceUri := Uri;
  end
  else
  begin
    ResolveName(Name, Position, False, Uri, Local);
    FNodes[Step].NodeTest := xntName;
    FNodes[Step].NamespaceUri := Uri;
    FNodes[Step].LocalName := Local;
  end;
  Next;
  Result := True;
end;

procedure TParser.ParsePredicates(Node: Integer);
begin
  while IsSymbol('[') do
  begin
    Next;
    AddPredicate(Node, ParseExpr);
    Expect(']');
  end;
end;

function TParser.ParsePrimary: Integer;
var
  Uri, Local, Key: TLandrixXmlUtf8;
  I, Slot: Integer;
begin
  case FToken.Kind of
    tkString:
      begin
        Result := NewNode(xakString, FToken.Position);
        FNodes[Result].Text := FToken.Text;
        Next;
      end;
    tkInteger:
      begin
        Result := NewNode(xakInteger, FToken.Position);
        FNodes[Result].Decimal := LandrixXmlParseDecimal(FToken.Text);
        Next;
      end;
    tkDecimal:
      begin
        Result := NewNode(xakDecimal, FToken.Position);
        FNodes[Result].Decimal := LandrixXmlParseDecimal(FToken.Text);
        Next;
      end;
    tkDouble:
      begin
        Result := NewNode(xakDouble, FToken.Position);
        FNodes[Result].DoubleValue := LandrixXmlDoubleParse(FToken.Text);
        Next;
      end;
    tkVariable:
      begin
        Result := NewNode(xakVariable, FToken.Position);
        ResolveName(FToken.Text, FToken.Position, False, Uri, Local);
        Key := Uri + #0 + Local;
        Slot := -1;
        for I := FLocalCount - 1 downto 0 do
          if FLocalNames[I] = Key then
          begin
            Slot := FLocalSlots[I];
            Break;
          end;
        if Slot < 0 then
          Slot := FContext.FindVariable(Uri, Local);
        if Slot < 0 then
          ErrorCode('XPST0008', 'the variable $' + LandrixXmlUtf8ToString(FToken.Text) + ' is not declared',
            FToken.Position);
        FNodes[Result].Slot := Slot;
        Next;
      end;
    tkName:
      begin
        if not NextIsSymbol('(') then
          Error('unexpected "' + LandrixXmlUtf8ToString(FToken.Text) + '"', FToken.Position);
        Result := ParseFunctionCall(FToken.Text, FToken.Position);
      end;
    tkSymbol:
      if IsSymbol('.') then
      begin
        Result := NewNode(xakContextItem, FToken.Position);
        Next;
      end
      else if IsSymbol('(') then
      begin
        Next;
        if IsSymbol(')') then
        begin
          Result := NewNode(xakEmpty, FToken.Position);
          Next;
        end
        else
        begin
          Result := ParseExpr;
          Expect(')');
        end;
      end
      else
      begin
        Error('unexpected "' + LandrixXmlUtf8ToString(FToken.Text) + '"', FToken.Position);
        Result := -1;
      end;
  else
    Error('unexpected end of the expression', FToken.Position);
    Result := -1;
  end;
end;

function TParser.ParseFunctionCall(const AName: TLandrixXmlUtf8; Position: Integer): Integer;
var
  Name, Uri, Local: TLandrixXmlUtf8;
  Id: TLandrixXmlXPathFunctionId;
  Found: Boolean;
  Args, User: Integer;

  { round and string-join have other arities only from XPath 3.0 on }
  function ArityIn20(F: TLandrixXmlXPathFunctionId; Count: Integer): Boolean;
  begin
    if FContext.Profile <> xppXPath20 then
      Result := True
    else
      case F of
        xfnRound: Result := Count = 1;
        xfnStringJoin: Result := Count = 2;
      else
        Result := True;
      end;
  end;

begin
  { AName may be the current token's text, which Next replaces; the
    local variable keeps its own reference }
  Name := AName;
  if (Name = 'if') or (Name = 'typeswitch') or (Name = 'item') or (Name = 'empty-sequence') then
    Error('unexpected "' + LandrixXmlUtf8ToString(Name) + '("', Position);
  ResolveName(Name, Position, True, Uri, Local);
  Result := NewNode(xakFunction, Position);
  Next;
  Expect('(');
  if not IsSymbol(')') then
  begin
    AddChild(Result, ParseExprSingle);
    while IsSymbol(',') do
    begin
      Next;
      AddChild(Result, ParseExprSingle);
    end;
  end;
  Expect(')');
  Args := Integer(Length(FNodes[Result].Children));
  { a user function first, then the built-ins }
  User := FContext.FindFunction(Uri, Local, Args);
  if User >= 0 then
  begin
    FNodes[Result].Op := -1 - User;
    Exit;
  end;
  Found := False;
  for Id := Low(TLandrixXmlXPathFunctionId) to High(TLandrixXmlXPathFunctionId) do
    if (LandrixXmlStringToUtf8(Functions[Id].Name) = Local) and
      ((Functions[Id].Xs and (Uri = LandrixXmlXPathSchemaNamespace)) or
      (not Functions[Id].Xs and (Uri = LandrixXmlXPathFunctionNamespace))) then
    begin
      Found := True;
      if (Args < Functions[Id].MinArgs) or ((Functions[Id].MaxArgs >= 0) and (Args > Functions[Id].MaxArgs)) or
        not ArityIn20(Id, Args) then
        ErrorCode('XPST0017', 'wrong number of arguments for ' + LandrixXmlXPathFunctionName(Id) + '()', Position);
      FNodes[Result].Op := Ord(Id);
      if Functions[Id].Xs then
        FNodes[Result].AtomicType := LandrixXmlXPathAtomicTypeByName(Local);
      Break;
    end;
  if not Found then
    ErrorCode('XPST0017', 'unknown function ' + LandrixXmlUtf8ToString(Name) + '#' + IntToStr(Args), Position);
end;

{ --- sequence types --------------------------------------------------- }

function LandrixXmlXPathParseSequenceType(const Text: TLandrixXmlUtf8;
  Context: TLandrixXmlXPathStaticContext): TLandrixXmlXPathSequenceType;
var
  P: TParser;
begin
  P := TParser.Create(Text, Context);
  try
    P.Next;
    Result := P.ParseSequenceType;
    if P.FToken.Kind <> tkEnd then
      P.Error('unexpected "' + LandrixXmlUtf8ToString(P.FToken.Text) + '"', P.FToken.Position);
  finally
    P.Free;
  end;
end;

function LandrixXmlXPathSequenceTypeName(const T: TLandrixXmlXPathSequenceType): string;

  function NameText: string;
  begin
    if T.LocalName = '' then
      Result := '*'
    else if T.NamespaceUri = '' then
      Result := LandrixXmlUtf8ToString(T.LocalName)
    else
      Result := 'Q{' + LandrixXmlUtf8ToString(T.NamespaceUri) + '}' + LandrixXmlUtf8ToString(T.LocalName);
  end;

  function NameAndType: string;
  begin
    Result := '';
    if T.ContentType <> '' then
    begin
      Result := NameText + ', xs:' + LandrixXmlUtf8ToString(T.ContentType);
      if T.Nilled then
        Result := Result + '?';
    end
    else if T.LocalName <> '' then
      Result := NameText;
  end;

begin
  case T.Kind of
    xtkEmpty:
      begin
        Result := 'empty-sequence()';
        Exit;
      end;
    xtkAtomic:
      Result := LandrixXmlXPathAtomicTypeName(T.AtomicType);
    xtkNode:
      case T.KindTest of
        xktDocument:
          if T.ElementTest then
            Result := 'document-node(element(' + NameAndType + '))'
          else
            Result := 'document-node()';
        xktElement: Result := 'element(' + NameAndType + ')';
        xktAttribute: Result := 'attribute(' + NameAndType + ')';
        xktText: Result := 'text()';
        xktComment: Result := 'comment()';
        xktProcessingInstruction:
          Result := 'processing-instruction(' + LandrixXmlUtf8ToString(T.LocalName) + ')';
      else
        Result := 'node()';
      end;
  else
    Result := 'item()';
  end;
  case T.Occurrence of
    xocOptional: Result := Result + '?';
    xocMany: Result := Result + '*';
    xocOneOrMore: Result := Result + '+';
  else
    { exactly one }
  end;
end;

{ --- TLandrixXmlXPathExpression ---------------------------------------- }

constructor TLandrixXmlXPathExpression.Create(const Text: TLandrixXmlUtf8; Context: TLandrixXmlXPathStaticContext);
var
  P: TParser;
begin
  inherited Create;
  FText := Text;
  CounterLock.BeginWrite;
  try
    Inc(ExpressionCounter);
    FSerial := ExpressionCounter;
  finally
    CounterLock.EndWrite;
  end;
  P := TParser.Create(Text, Context);
  try
    FRoot := P.Parse;
    FNodes := Copy(P.FNodes, 0, P.FCount);
    FSlotCount := P.FSlotCount;
    FFirstLocalSlot := P.FContext.VariableCount;
    FProfile := P.FContext.Profile;
  finally
    P.Free;
  end;
end;

function TLandrixXmlXPathExpression.GetNode(Index: Integer): TLandrixXmlXPathAstNode;
begin
  Result := FNodes[Index];
end;

function TLandrixXmlXPathExpression.GetNodeCount: Integer;
begin
  Result := Integer(Length(FNodes));
end;

initialization
  CounterLock := TMultiReadExclusiveWriteSynchronizer.Create;

finalization
  CounterLock.Free;

end.
