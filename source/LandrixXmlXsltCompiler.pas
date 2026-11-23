{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Internal unit of the XSLT processor (LandrixXmlXslt), not part of the
  documented API: the compiled form of a stylesheet (instructions,
  templates, modes, global variables) and the compiler that reads the
  stylesheet modules into it.

  Every XPath expression is compiled with a static context of its own:
  the namespaces in scope at its element, and the variables visible there
  in slot order (the globals in slots 0 to GlobalCount - 1, the
  parameters and local variables of the template or function after them,
  each binding in a slot of its own; a name shadowed by a later binding is
  replaced by a placeholder that no reference can match). The functions
  are declared in the same order in every context, so that their index
  is that of the definitions the runtime builds (Functions).

  A global variable whose value is a sequence constructor is bound as the
  call xsl-internal-f:global(N) (a function the runtime implements), so
  that it is evaluated on first use like the others. current() is a
  function of the runtime too (the context item of the instruction, also
  an atomic one). doc(), doc-available() and document() resolve relative
  URIs against the module they are written in: each module has its own
  definitions, declared under the fn names in the contexts of that module
  only. }

unit LandrixXmlXsltCompiler;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  Contnrs,
  LandrixXmlBase,
  LandrixXmlXPathTree,
  LandrixXmlXPath,
  LandrixXmlXPathEval,
  LandrixXmlXslt,
  LandrixXmlXsltOutput,
  LandrixXmlXPathFormat;

const
  XsltNamespace = 'http://www.w3.org/1999/XSL/Transform';
  { the namespace of the functions the runtime adds (global) }
  XsltInternalNamespace = 'urn:landrix:xslt-internal';

  { the fixed functions, in this order in every static context }
  XfnGlobal = 0;
  XfnCurrent = 1;
  { format-dateTime, format-date, format-time with 2 and 5 arguments }
  XfnFormatDateTime2 = 2;
  XfnFormatDateTime5 = 3;
  XfnFormatDate2 = 4;
  XfnFormatDate5 = 5;
  XfnFormatTime2 = 6;
  XfnFormatTime5 = 7;
  { current-group(), current-grouping-key(), generate-id() with 0 and 1,
    key() with 2 and 3 arguments }
  XfnCurrentGroup = 8;
  XfnCurrentGroupingKey = 9;
  XfnGenerateId0 = 10;
  XfnGenerateId1 = 11;
  XfnKey2 = 12;
  XfnKey3 = 13;
  { format-number() with 2 and 3 arguments }
  XfnFormatNumber2 = 14;
  XfnFormatNumber3 = 15;
  { system-property#1, function-available#1/#2, element-available#1 }
  XfnSystemProperty = 16;
  XfnFunctionAvailable1 = 17;
  XfnFunctionAvailable2 = 18;
  XfnElementAvailable = 19;
  { regex-group#1 }
  XfnRegexGroup = 20;
  XfnFixedCount = 21;
  { then per static base URI (each module's URI, then those xml:base
    gives elements of the modules): doc#1, doc-available#1, document#1,
    document#2, static-base-uri#0, resolve-uri#1, unparsed-text#1/#2,
    unparsed-text-available#1/#2 }
  XfnPerModule = 10;
  XfnDoc = 0;
  XfnDocAvailable = 1;
  XfnDocument = 2;
  XfnDocument2 = 3;
  XfnStaticBaseUri = 4;
  XfnResolveUri = 5;
  XfnUnparsedText1 = 6;
  XfnUnparsedText2 = 7;
  XfnUnparsedTextAvailable1 = 8;
  XfnUnparsedTextAvailable2 = 9;

{ Whether the compiler translates the XSLT element with this local name
  (element-available(): instructions and declarations; false for those
  it rejects as unsupported). }
function XsltElementAvailable(const Local: TLandrixXmlUtf8): Boolean;

{ The Clark name of the format of xsl:result-document: a QName with the
  given namespaces (no default namespace) or an EQName (Q, the URI in braces, the local name; as
  Saxon accepts it); '' if it is neither or the prefix is not declared. }
function XsltFormatClark(const Name: TLandrixXmlUtf8; const Prefixes, Uris: TLandrixXmlUtf8Array): TLandrixXmlUtf8;

{ The Clark names (separated by spaces) of a cdata-section-elements value:
  QNames separated by white space (an unprefixed one in the default
  namespace of Prefixes and Uris) or EQNames. False, with Bad the first
  one, if a name is neither or its prefix is not declared. }
function XsltCDataNames(const Value: TLandrixXmlUtf8; const Prefixes, Uris: TLandrixXmlUtf8Array;
  out Names, Bad: TLandrixXmlUtf8): Boolean;

{ How a collation URI is treated: 0 the Unicode codepoint collation (the
  only one supported), 1 a collation Saxon recognizes (UCA, Saxon's own,
  html-ascii-case-insensitive): not supported, 2 a URI that is not
  recognized as a collation (the error of the instruction). }
function XsltCollationKind(const Uri: TLandrixXmlUtf8): Integer;

type
  { a string list that compares byte by byte (TStringList compares by the
    locale: AnsiCompareStr) }
  TXsltStringList = class(TStringList)
  protected
{$IFDEF FPC}
    function DoCompareText(const S1, S2: string): PtrInt; override;
{$ELSE}
    function CompareStrings(const S1, S2: string): Integer; override;
{$ENDIF}
  end;

  TXsltInstrKind = (xskLiteralElement, xskText, xskValueOf, xskApplyTemplates, xskCallTemplate,
    xskVariable, xskIf, xskChoose, xskWhen, xskForEach, xskSequence, xskCopyOf, xskCopy,
    xskElement, xskAttribute, xskComment, xskProcessingInstruction, xskMessage, xskDocument,
    xskNumber, xskNamespace, xskForEachGroup, xskPerformSort, xskAnalyzeString, xskNextMatch,
    xskApplyImports, xskResultDocument, xskUseAttributeSets, xskExtension, xskIterate, xskBreak,
    xskNextIteration);

  { a value with literal parts and expressions in curly brackets: Exprs[I] nil for a
    literal part }
  TXsltAvt = class
  public
    Parts: TLandrixXmlUtf8Array;
    Exprs: array of TLandrixXmlXPathExpression;
    function IsLiteral: Boolean;
  end;

  TXsltInstr = class;

  { one xsl:sort: the key (Select, or the sequence constructor in Body)
    and its attribute value templates (nil where the attribute is absent) }
  TXsltSortKey = class
  public
    Select: TLandrixXmlXPathExpression;
    Body: TObjectList;
    Order: TXsltAvt;
    DataType: TXsltAvt;
    CaseOrder: TXsltAvt;
    Collation: TXsltAvt;
    Stable: TXsltAvt;
    { the xsl:sort element, for the position of its errors (owned) }
    Where: TXsltInstr;
    constructor Create;
    destructor Destroy; override;
  end;

  TXsltAttributeTemplate = class
  public
    NamespaceUri: TLandrixXmlUtf8;
    Prefix: TLandrixXmlUtf8;
    LocalName: TLandrixXmlUtf8;
    Value: TXsltAvt;
  end;

  { xsl:with-param, or a parameter supplied to a template }
  TXsltWithParam = class
  public
    Name: TLandrixXmlUtf8;
    { the static base URI (of a temporary tree its body makes) }
    BaseUri: TLandrixXmlUtf8;
    { tunnel="yes": passed on to the templates the called one invokes }
    Tunnel: Boolean;
    Select: TLandrixXmlXPathExpression;
    Body: TObjectList;
    HasAs: Boolean;
    AsType: TLandrixXmlXPathSequenceType;
    { xsl:with-param of xsl:next-iteration: the parameter of the
      xsl:iterate it sets (not owned) }
    Target: TXsltInstr;
    constructor Create;
    destructor Destroy; override;
  end;

  TXsltInstr = class
  public
    Kind: TXsltInstrKind;
    Module: TLandrixXmlUtf8;
    { the static base URI (xml:base applied): the base URI of a temporary
      tree it makes }
    BaseUri: TLandrixXmlUtf8;
    Line: Integer;
    Column: Integer;
    { processed in backwards compatible mode (a version below 2.0) }
    Backwards: Boolean;
    { the sequence constructor (TXsltInstr, owned) }
    Body: TObjectList;
    Select: TLandrixXmlXPathExpression;
    Test: TLandrixXmlXPathExpression;
    Text: TLandrixXmlUtf8;
    { a literal result element and its namespaces and attributes }
    NamespaceUri: TLandrixXmlUtf8;
    Prefix: TLandrixXmlUtf8;
    LocalName: TLandrixXmlUtf8;
    NsPrefixes: TLandrixXmlUtf8Array;
    NsUris: TLandrixXmlUtf8Array;
    Attributes: TObjectList;
    { xsl:element, xsl:attribute, xsl:processing-instruction: the name and
      namespace; xsl:value-of: the separator; xsl:message: terminate }
    NameAvt: TXsltAvt;
    NamespaceAvt: TXsltAvt;
    { xsl:value-of, xsl:attribute: the separator }
    Separator: TXsltAvt;
    { the namespaces to resolve a computed name with (xsl:element,
      xsl:attribute) }
    ScopePrefixes: TLandrixXmlUtf8Array;
    ScopeUris: TLandrixXmlUtf8Array;
    { apply-templates: the mode (TXsltMode), CurrentMode for #current;
      call-template: the template (TXsltTemplate) }
    Mode: TObject;
    CurrentMode: Boolean;
    { apply-templates without select (child::node(): XTTE0510 for an
      atomic context item) }
    ImplicitSelect: Boolean;
    Template: TObject;
    { with-param (TXsltWithParam, owned) }
    Params: TObjectList;
    { xsl:variable, xsl:param of a template: the slot and name (Clark);
      Tunnel: a tunnel parameter }
    Slot: Integer;
    VarName: TLandrixXmlUtf8;
    IsParam: Boolean;
    Tunnel: Boolean;
    Required: Boolean;
    HasAs: Boolean;
    AsType: TLandrixXmlXPathSequenceType;
    { an extension instruction (no extension is known): whether it has
      xsl:fallback (Body: the content of each, in order; none:
      XTDE1450 when it is evaluated), Text its name }
    HasFallback: Boolean;
    { xsl:choose: the xsl:when branches (owned); Body is xsl:otherwise }
    Branches: TObjectList;
    { xsl:number: the level (0 single, 1 multiple, 2 any), the branches of
      the count and from patterns (none: the default count pattern), the
      value, the format and the grouping (nil if not given) }
    NumberLevel: Integer;
    { xsl:for-each-group: 0 group-by, 1 group-adjacent (the key in Test),
      2 group-starting-with, 3 group-ending-with (the pattern in
      CountPatterns) }
    GroupKind: Integer;
    CountPatterns: array of TLandrixXmlXPathExpression;
    CountRelative: array of Boolean;
    FromPatterns: array of TLandrixXmlXPathExpression;
    FromRelative: array of Boolean;
    NumberValue: TLandrixXmlXPathExpression;
    FormatAvt: TXsltAvt;
    { xsl:number lang, ordinal and letter-value (nil if absent; a
      literal empty lang counts as absent, as Saxon) }
    NumberLang, NumberOrdinal, LetterValue: TXsltAvt;
    GroupingSeparator: TXsltAvt;
    GroupingSize: TXsltAvt;
    { xsl:for-each-group: the collation (nil if absent) }
    CollationAvt: TXsltAvt;
    { xsl:text, xsl:value-of: disable-output-escaping="yes" }
    NoEscape: Boolean;
    { xsl:copy, xsl:copy-of: copy-namespaces="no" }
    NoNamespaces: Boolean;
    { xskText: a text value template (expand-text="yes"; nil for literal
      text, which is Text) }
    TextAvt: TXsltAvt;
    { xsl:for-each, xsl:apply-templates, xsl:for-each-group,
      xsl:perform-sort: the sort keys (TXsltSortKey, owned; nil if none) }
    SortKeys: TObjectList;
    { xsl:analyze-string: regex and flags (nil if absent); Body is
      xsl:matching-substring, NonMatching xsl:non-matching-substring
      (owned; xskExtension: its other children, compiled for their static
      errors only) }
    RegexAvt: TXsltAvt;
    FlagsAvt: TXsltAvt;
    NonMatching: TObjectList;
    { xsl:result-document: href (nil if absent), the format in FormatAvt
      (nil if absent; a literal one is checked when compiled) and the
      serialization attributes: the output property names (output-version
      as version) and their attribute value templates }
    HrefAvt: TXsltAvt;
    OutputNames: TLandrixXmlUtf8Array;
    OutputAvts: array of TXsltAvt;
    { cdata-section-elements (nil if absent): added to the output
      definition's }
    CDataAvt: TXsltAvt;
    { a literal result element, xsl:element, xsl:copy: the attribute sets
      it uses (an xskUseAttributeSets, owned; nil if none);
      xskUseAttributeSets: the names (Clark) and, resolved, the
      xsl:attribute-set declarations they expand to in order (TXsltTemplate
      each, not owned) }
    { a literal result element: the namespaces exclude-result-prefixes
      left out (an aliased one is copied all the same) }
    ExPrefixes: TLandrixXmlUtf8Array;
    ExUris: TLandrixXmlUtf8Array;
    UseSets: TXsltInstr;
    SetNames: TLandrixXmlUtf8Array;
    Sets: TList;
    { xsl:result-document: the character map of its use-character-maps
      (a TXsltOutputProperties with the mappings only, owned; nil if
      none), added to that of the output definition }
    MapProps: TObject;
    { xsl:iterate: its xsl:on-completion (an xskSequence with Select or
      Body, owned; nil if none); the parameters are in Branches
      (xskVariable with IsParam, owned) }
    Completion: TXsltInstr;
    constructor Create(AKind: TXsltInstrKind);
    destructor Destroy; override;
  end;

  TXsltTemplate = class
  public
    Name: TLandrixXmlUtf8;
    Module: TLandrixXmlUtf8;
    Line: Integer;
    Column: Integer;
    { the parameters (xskVariable with IsParam, owned) }
    Params: TObjectList;
    Body: TObjectList;
    FrameSize: Integer;
    Precedence: Integer;
    HasAs: Boolean;
    AsType: TLandrixXmlXPathSequenceType;
    constructor Create;
    destructor Destroy; override;
  end;

  TXsltRule = class
  public
    Template: TXsltTemplate;
    Pattern: TLandrixXmlXPathExpression;
    Relative: Boolean;
    Priority: Double;
    Precedence: Integer;
    Order: Integer;
    { the template has a priority attribute: the branches of a union
      pattern are one rule (xsl:next-match does not choose the template
      again, as in Saxon) }
    Explicit: Boolean;
  end;

  { on-no-match of xsl:mode: the built-in template rules }
  TXsltOnNoMatch = (xnmTextOnlyCopy, xnmDeepCopy, xnmShallowCopy, xnmDeepSkip, xnmShallowSkip, xnmFail);

  TXsltMode = class
  public
    Name: TLandrixXmlUtf8;
    { the properties xsl:mode declarations give (XSLT 3.0): the built-in
      rules, on-multiple-match="fail" (XTDE0540), typed yes, lax or strict
      (XTTE3100 for an element or attribute node xsl:apply-templates
      selects; no node is typed); for the initial mode (Saxon): an xsl:mode
      says visibility="private" (no default visibility: Saxon starts
      such a mode), an xsl:mode gives on-no-match }
    OnNoMatch: TXsltOnNoMatch;
    FailOnMultiple: Boolean;
    Typed: Boolean;
    IsPrivate: Boolean;
    NoMatchGiven: Boolean;
    { the rules whose pattern names an element or attribute (by kind and
      Clark name: "e" or "a" before the Clark name), each a TList of TXsltRule
      in the order they are tried; the others in Others }
    Named: TStringList;
    Others: TList;
    constructor Create;
    destructor Destroy; override;
  end;

  TXsltGlobal = class
  public
    Name: TLandrixXmlUtf8;
    Lexical: TLandrixXmlUtf8;
    Module: TLandrixXmlUtf8;
    { the static base URI (of a temporary tree its body makes) }
    BaseUri: TLandrixXmlUtf8;
    Line: Integer;
    Column: Integer;
    Slot: Integer;
    IsParam: Boolean;
    Required: Boolean;
    Select: TLandrixXmlXPathExpression;
    Body: TObjectList;
    { xsl-internal-f:global(Slot) for a body }
    Call: TLandrixXmlXPathExpression;
    FrameSize: Integer;
    Precedence: Integer;
    HasAs: Boolean;
    AsType: TLandrixXmlXPathSequenceType;
    constructor Create;
    destructor Destroy; override;
  end;

  { one xsl:key declaration: its match pattern branches and use }
  TXsltKeyDecl = class
  public
    Patterns: array of TLandrixXmlXPathExpression;
    Relative: array of Boolean;
    { the use expression, or nil and the sequence constructor in Body
      (TXsltInstr, owned) with its frame size }
    Use: TLandrixXmlXPathExpression;
    Body: TObjectList;
    FrameSize: Integer;
    { backwards compatible mode: the values are indexed as strings }
    Backwards: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;

  { the declarations of a key name (TXsltKeyDecl, owned) }
  TXsltKey = class
  public
    Name: TLandrixXmlUtf8;
    Index: Integer;
    Decls: TObjectList;
    constructor Create;
    destructor Destroy; override;
  end;

  TXsltCompiled = class
  public
    Globals: TObjectList;
    GlobalCount: Integer;
    Templates: TObjectList;
    Rules: TObjectList;
    { mode name ('' the default) -> TXsltMode }
    Modes: TStringList;
    { template name -> TXsltTemplate }
    NamedTemplates: TStringList;
    { attribute set name (Clark) -> TList of its xsl:attribute-set
      declarations (TXsltTemplate each, owned by Templates) in order of
      import precedence, then declaration order; the list is owned }
    AttributeSets: TStringList;
    Expressions: TObjectList;
    Output: TXsltOutputProperties;
    { the named output definitions (xsl:output with name): Clark name ->
      TXsltOutputProperties, owned }
    NamedOutputs: TStringList;
    { the functions of every static context (see the unit comment) }
    FunctionUris: TLandrixXmlUtf8Array;
    FunctionNames: TLandrixXmlUtf8Array;
    FunctionArities: array of Integer;
    FunctionFlags: array of TLandrixXmlXPathFunctionFlags;
    { the module a function belongs to (-1: all), and the modules' URIs }
    FunctionModules: array of Integer;
    ModuleUris: TLandrixXmlUtf8Array;
    { the stylesheet functions (xsl:function, a TXsltTemplate each, owned
      by Templates): function UserFunctionBase + I is UserFunctions[I] }
    UserFunctions: TList;
    UserFunctionBase: Integer;
    { key name (Clark) -> TXsltKey, owned }
    Keys: TStringList;
    { decimal format name ('' the default) -> TXPathDecimalFormat, owned }
    DecimalFormats: TStringList;
    { the name tests of xsl:strip-space and xsl:preserve-space: kind 0 a
      name (URI and local name), 1 "prefix:*" (URI), 2 "*", 3 "*:name"
      (local name); strip or
      preserve; import precedence and declaration order. HasStrip: there
      is an xsl:strip-space (else no source is changed). }
    SpaceKinds: array of Integer;
    SpaceUris: TLandrixXmlUtf8Array;
    SpaceLocals: TLandrixXmlUtf8Array;
    SpaceStrip: array of Boolean;
    SpacePrecedences: array of Integer;
    SpaceOrders: array of Integer;
    HasStrip: Boolean;
    { for each import precedence (a stylesheet level): the lowest
      precedence of the modules imported into it (xsl:apply-imports
      considers the rules from there to the precedence below its own) }
    ImportLow: array of Integer;
    { the mode of the transformation when no initial mode is given: the
      [xsl:]default-mode of the principal module's root element ('' the
      unnamed mode) }
    DefaultMode: TLandrixXmlUtf8;
    constructor Create;
    destructor Destroy; override;
    function FindMode(const Name: TLandrixXmlUtf8): TXsltMode;
    function FindGlobal(const Name: TLandrixXmlUtf8): TXsltGlobal;
  end;

{ Whether white space text children of an element with this name are
  stripped from a source document (xsl:strip-space and
  xsl:preserve-space: the test of the highest import precedence, then of
  the highest priority, a name before "prefix:*" before "*", then the last
  one; none: preserved). }
function XsltStripsSpace(C: TXsltCompiled; const NamespaceUri, LocalName: TLandrixXmlUtf8): Boolean;

{ The functions system-property(), function-available() and
  element-available() share (at run time and in use-when): the lexical
  QName in Arg (one string, white space around it allowed) as a URI and a
  local name, the prefix by the stylesheet's namespaces at the calling
  expression ('#ns:' keys of the static context), no prefix: DefaultUri,
  or the default namespace if DefaultUri is '#'; Code for a name that is
  none or has an unbound prefix. }
procedure XsltNameArgument(Evaluator: TLandrixXmlXPathEvaluator; const Arg: TLandrixXmlXPathSequence;
  const Code, FunctionName: string; const DefaultUri: TLandrixXmlUtf8; out Uri, Local: TLandrixXmlUtf8);
{ the value of system-property() for a name }
function XsltSystemProperty(const Uri, Local: TLandrixXmlUtf8): TLandrixXmlUtf8;
{ the second argument of function-available(): the arity, -1 for a
  negative one (any, as Saxon), MaxInt for one beyond Integer }
function XsltArityArgument(Evaluator: TLandrixXmlXPathEvaluator; const Arg: TLandrixXmlXPathSequence): Integer;
{ function-available(): an XPath function of the calling expression's
  profile or a function of the stylesheet's table (not the internal
  global(), not document() with two arguments); while the table is still
  empty (use-when) the XSLT functions of this processor; Arity -1: any }
function XsltFunctionAvailable(Evaluator: TLandrixXmlXPathEvaluator; FC: TXsltCompiled;
  const Uri, Local: TLandrixXmlUtf8; Arity: Integer): Boolean;

{ Compiles the stylesheet whose principal module is Tree (BaseUri its
  URI). Raises ELandrixXmlXsltError. }
function XsltCompile(Tree: TLandrixXmlXPathTree; const BaseUri: TLandrixXmlUtf8;
  Resolver: TLandrixXmlXsltResolver): TObject;
function XsltParameterCount(Compiled: TObject): Integer;
function XsltParameterName(Compiled: TObject; Index: Integer): TLandrixXmlUtf8;
function XsltParameterRequired(Compiled: TObject; Index: Integer): Boolean;
{ a copy of the stylesheet's output properties; the caller frees it }
function XsltOutputProperties(Compiled: TObject): TXsltOutputProperties;
{ the Clark name of an expanded name }
function XsltClarkOf(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlUtf8;

implementation

uses
  LandrixXmlReader,
  LandrixXmlConvert,
  LandrixXmlRegex;

{$IFDEF FPC}
function TXsltStringList.DoCompareText(const S1, S2: string): PtrInt;
{$ELSE}
function TXsltStringList.CompareStrings(const S1, S2: string): Integer;
{$ENDIF}
begin
  Result := CompareStr(S1, S2);
end;

constructor TXsltKeyDecl.Create;
begin
  inherited Create;
  Body := TObjectList.Create;
end;

destructor TXsltKeyDecl.Destroy;
begin
  Body.Free;
  inherited Destroy;
end;

constructor TXsltKey.Create;
begin
  inherited Create;
  Decls := TObjectList.Create;
end;

destructor TXsltKey.Destroy;
begin
  Decls.Free;
  inherited Destroy;
end;

{ the priority of a name test kind as a rank: a name 0, "prefix:*" and
  "*:name" 1, "*" 2 }
function SpaceRank(Kind: Integer): Integer;
begin
  if Kind = 3 then
    Result := 1
  else
    Result := Kind;
end;

function XsltStripsSpace(C: TXsltCompiled; const NamespaceUri, LocalName: TLandrixXmlUtf8): Boolean;
var
  I, Best: Integer;
  Matches: Boolean;
begin
  Best := -1;
  for I := 0 to Integer(Length(C.SpaceKinds)) - 1 do
  begin
    case C.SpaceKinds[I] of
      0: Matches := (C.SpaceUris[I] = NamespaceUri) and (C.SpaceLocals[I] = LocalName);
      1: Matches := C.SpaceUris[I] = NamespaceUri;
      3: Matches := C.SpaceLocals[I] = LocalName;
    else
      Matches := True;
    end;
    if Matches and ((Best < 0) or (C.SpacePrecedences[I] > C.SpacePrecedences[Best]) or
      (C.SpacePrecedences[I] = C.SpacePrecedences[Best]) and
      ((SpaceRank(C.SpaceKinds[I]) < SpaceRank(C.SpaceKinds[Best])) or
      (SpaceRank(C.SpaceKinds[I]) = SpaceRank(C.SpaceKinds[Best])) and (C.SpaceOrders[I] > C.SpaceOrders[Best]))) then
      Best := I;
  end;
  Result := (Best >= 0) and C.SpaceStrip[Best];
end;

function XsltClarkOf(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlUtf8;
begin
  if NamespaceUri = '' then
    Result := LocalName
  else
    Result := '{' + NamespaceUri + '}' + LocalName;
end;

function XsltElementAvailable(const Local: TLandrixXmlUtf8): Boolean;
const
  { the XSLT elements CompileInstruction and the declaration loop
    translate (the others are rejected) }
  Names: array[0..50] of string = ('stylesheet', 'transform', 'import', 'include', 'output', 'key',
    'decimal-format', 'template', 'function', 'variable', 'param', 'with-param', 'apply-templates',
    'call-template', 'choose', 'when', 'otherwise', 'if', 'for-each', 'for-each-group', 'number',
    'sequence', 'copy', 'copy-of', 'element', 'attribute', 'comment', 'processing-instruction',
    'message', 'document', 'text', 'value-of', 'fallback', 'sort', 'perform-sort', 'analyze-string',
    'strip-space', 'preserve-space', 'next-match', 'apply-imports', 'result-document',
    'attribute-set', 'character-map', 'output-character', 'namespace', 'namespace-alias', 'iterate',
    'next-iteration', 'break', 'on-completion', 'mode');
var
  I: Integer;
begin
  Result := True;
  for I := Low(Names) to High(Names) do
    if LandrixXmlStringToUtf8(Names[I]) = Local then
      Exit;
  Result := False;
end;

{ the byte index of Sub in S (0 if none), without a conversion to string }
function Pos8(const Sub, S: TLandrixXmlUtf8): Integer;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) - Length(Sub) + 1 do
  begin
    J := 1;
    while (J <= Length(Sub)) and (S[I + J - 1] = Sub[J]) do
      Inc(J);
    if J > Length(Sub) then
    begin
      Result := I;
      Exit;
    end;
  end;
end;

{ --- the compiled form ------------------------------------------------------ }

function TXsltAvt.IsLiteral: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to Integer(Length(Exprs)) - 1 do
    if Exprs[I] <> nil then
      Exit;
  Result := True;
end;

constructor TXsltWithParam.Create;
begin
  inherited Create;
  Body := TObjectList.Create;
end;

destructor TXsltWithParam.Destroy;
begin
  Body.Free;
  inherited Destroy;
end;

constructor TXsltInstr.Create(AKind: TXsltInstrKind);
begin
  inherited Create;
  Kind := AKind;
  Body := TObjectList.Create;
  Attributes := TObjectList.Create;
  Params := TObjectList.Create;
  Branches := TObjectList.Create;
  Slot := -1;
end;

destructor TXsltInstr.Destroy;
begin
  Completion.Free;
  MapProps.Free;
  Sets.Free;
  UseSets.Free;
  NonMatching.Free;
  SortKeys.Free;
  Branches.Free;
  Params.Free;
  Attributes.Free;
  Body.Free;
  inherited Destroy;
end;

constructor TXsltSortKey.Create;
begin
  inherited Create;
  Body := TObjectList.Create;
end;

destructor TXsltSortKey.Destroy;
begin
  Where.Free;
  Body.Free;
  inherited Destroy;
end;

constructor TXsltTemplate.Create;
begin
  inherited Create;
  Params := TObjectList.Create;
  Body := TObjectList.Create;
end;

destructor TXsltTemplate.Destroy;
begin
  Body.Free;
  Params.Free;
  inherited Destroy;
end;

constructor TXsltMode.Create;
begin
  inherited Create;
  Named := TXsltStringList.Create;
  Named.CaseSensitive := True;
  Named.Sorted := True;
  Named.Duplicates := dupError;
  Others := TList.Create;
end;

destructor TXsltMode.Destroy;
var
  I: Integer;
begin
  for I := 0 to Integer(Named.Count) - 1 do
    Named.Objects[I].Free;
  Named.Free;
  Others.Free;
  inherited Destroy;
end;

constructor TXsltGlobal.Create;
begin
  inherited Create;
  Body := TObjectList.Create;
end;

destructor TXsltGlobal.Destroy;
begin
  Body.Free;
  inherited Destroy;
end;

constructor TXsltCompiled.Create;
begin
  inherited Create;
  Globals := TObjectList.Create;
  Templates := TObjectList.Create;
  Rules := TObjectList.Create;
  Modes := TXsltStringList.Create;
  Modes.CaseSensitive := True;
  Modes.Sorted := True;
  NamedTemplates := TXsltStringList.Create;
  NamedTemplates.CaseSensitive := True;
  NamedTemplates.Sorted := True;
  AttributeSets := TXsltStringList.Create;
  AttributeSets.CaseSensitive := True;
  AttributeSets.Sorted := True;
  Expressions := TObjectList.Create;
  Output := TXsltOutputProperties.Create;
  NamedOutputs := TXsltStringList.Create;
  NamedOutputs.CaseSensitive := True;
  NamedOutputs.Sorted := True;
  UserFunctions := TList.Create;
  Keys := TXsltStringList.Create;
  Keys.CaseSensitive := True;
  DecimalFormats := TXsltStringList.Create;
  DecimalFormats.CaseSensitive := True;
  DecimalFormats.AddObject('', TXPathDecimalFormat.Create);
end;

destructor TXsltCompiled.Destroy;
var
  I: Integer;
begin
  for I := 0 to Integer(Modes.Count) - 1 do
    Modes.Objects[I].Free;
  Modes.Free;
  NamedTemplates.Free;
  for I := 0 to Integer(AttributeSets.Count) - 1 do
    AttributeSets.Objects[I].Free;
  AttributeSets.Free;
  Rules.Free;
  Templates.Free;
  Globals.Free;
  Output.Free;
  for I := 0 to Integer(NamedOutputs.Count) - 1 do
    NamedOutputs.Objects[I].Free;
  NamedOutputs.Free;
  Expressions.Free;
  UserFunctions.Free;
  for I := 0 to Integer(Keys.Count) - 1 do
    Keys.Objects[I].Free;
  Keys.Free;
  for I := 0 to Integer(DecimalFormats.Count) - 1 do
    DecimalFormats.Objects[I].Free;
  DecimalFormats.Free;
  inherited Destroy;
end;

function TXsltCompiled.FindMode(const Name: TLandrixXmlUtf8): TXsltMode;
var
  I: Integer;
begin
  Result := nil;
  if Modes.Find(LandrixXmlUtf8ToKey(Name), I) then
    Result := TXsltMode(Modes.Objects[I]);
end;

function TXsltCompiled.FindGlobal(const Name: TLandrixXmlUtf8): TXsltGlobal;
var
  I: Integer;
begin
  for I := 0 to Integer(Globals.Count) - 1 do
    if TXsltGlobal(Globals[I]).Name = Name then
    begin
      Result := TXsltGlobal(Globals[I]);
      Exit;
    end;
  Result := nil;
end;

function XsltParameterCount(Compiled: TObject): Integer;
var
  I: Integer;
  C: TXsltCompiled;
begin
  C := TXsltCompiled(Compiled);
  Result := 0;
  for I := 0 to Integer(C.Globals.Count) - 1 do
    if TXsltGlobal(C.Globals[I]).IsParam then
      Inc(Result);
end;

function ParameterAt(Compiled: TObject; Index: Integer): TXsltGlobal;
var
  I: Integer;
  C: TXsltCompiled;
begin
  C := TXsltCompiled(Compiled);
  for I := 0 to Integer(C.Globals.Count) - 1 do
    if TXsltGlobal(C.Globals[I]).IsParam then
    begin
      if Index = 0 then
      begin
        Result := TXsltGlobal(C.Globals[I]);
        Exit;
      end;
      Dec(Index);
    end;
  raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'XSLT: no parameter with this index');
end;

function XsltParameterName(Compiled: TObject; Index: Integer): TLandrixXmlUtf8;
begin
  Result := ParameterAt(Compiled, Index).Name;
end;

function XsltParameterRequired(Compiled: TObject; Index: Integer): Boolean;
begin
  Result := ParameterAt(Compiled, Index).Required;
end;

function XsltOutputProperties(Compiled: TObject): TXsltOutputProperties;
begin
  Result := TXsltCompiled(Compiled).Output.Clone;
end;

{ --- compiler ---------------------------------------------------------------- }

type
  TModule = class
  public
    Tree: TLandrixXmlXPathTree;
    Uri: TLandrixXmlUtf8;
    Owned: Boolean;
    { its number (the functions doc(), document() of the module) }
    Index: Integer;
    { the modules its xsl:include elements read, by element }
    IncludeElements: array of Integer;
    IncludeModules: array of TModule;
    { the positions of the nodes in the module's text when Tree is the copy
      use-when made (empty otherwise) }
    Lines: array of Integer;
    Columns: array of Integer;
    { a simplified stylesheet module: a literal result element with
      xsl:version, a template rule for "/" }
    Simplified: Boolean;
    destructor Destroy; override;
    function IncludedAt(E: Integer): TModule;
    function LineOf(E: Integer): Integer;
    function ColumnOf(E: Integer): Integer;
  end;

  { a top-level declaration found in pass 1 }
  TDecl = class
  public
    Module: TModule;
    Element: Integer;
    Precedence: Integer;
    Order: Integer;
    { the literal result element of a simplified stylesheet module }
    Simplified: Boolean;
  end;

  { an output property set by xsl:output (Key: the Clark name of the
    output definition, a space and the attribute): the declaration of the
    highest import precedence so far, its value, and another one of the
    same precedence with a different value (XTSE1560 unless a higher one
    follows) }
  TOutputSeen = class
  public
    Key: TLandrixXmlUtf8;
    Decl: TDecl;
    Value: TLandrixXmlUtf8;
    Conflict: TDecl;
  end;

  { an xsl:character-map: its maps (use-character-maps, Clark names) and
    its characters with their strings }
  TCharMap = class
  public
    Module: TModule;
    Element: Integer;
    Precedence: Integer;
    { another map of the name and precedence (XTSE1580 unless one of a
      higher precedence replaces both) }
    Duplicate: Boolean;
    UseNames: TLandrixXmlUtf8Array;
    Chars: TXsltCardinalArray;
    Strings: TLandrixXmlUtf8Array;
  end;

  { an xsl:namespace-alias: the result namespace (prefix and URI) for
    the namespace of the stylesheet that the key names }
  TNamespaceAlias = class
  public
    Prefix: TLandrixXmlUtf8;
    Uri: TLandrixXmlUtf8;
    Precedence: Integer;
    { another alias of the precedence with another result (XTSE0810 unless
      one of a higher precedence replaces both) }
    Conflict: Boolean;
    Module: TModule;
    Element: Integer;
  end;

  { a use-character-maps (of xsl:output or xsl:result-document): the
    output properties that get the maps, composed by Finish (nil: the
    names of a replaced xsl:character-map, only checked) }
  TMapRef = class
  public
    Props: TXsltOutputProperties;
    Module: TModule;
    Element: Integer;
    Names: TLandrixXmlUtf8Array;
  end;

  { the variables visible at a point of a template or function body }
  TScope = class
  public
    Names: TLandrixXmlUtf8Array;
    Clarks: TLandrixXmlUtf8Array;
    Slots: array of Integer;
    Count: Integer;
    NextSlot: Integer;
    MaxSlot: Integer;
    procedure Add(const Lexical, Clark: TLandrixXmlUtf8; Slot: Integer);
  end;

  TCompiler = class
  private
    FResolver: TLandrixXmlXsltResolver;
    FOwnResolver: Boolean;
    FModules: TObjectList;
    FDecls: TObjectList;
    { the xsl:function declarations in force, in the order of
      FC.UserFunctions }
    FFunctionDecls: TList;
    FNextPrecedence: Integer;
    FNextOrder: Integer;
    FC: TXsltCompiled;
    { CompileAvt compiles a text value template: an empty expression is
      the empty sequence }
    FTextTemplate: Boolean;
    FAllModeTemplates: TList;
    { named templates with a name of the same precedence: XTSE0660 only
      if no template of higher precedence overrides them }
    FDupTemplates, FDupTemplateDecls: TList;
    { the evaluation of use-when: an empty tree, the definitions of the
      functions it answers, true() and false() (made on first use) }
    FUseWhenTree: TLandrixXmlXPathTree;
    FUseWhenEvaluator: TLandrixXmlXPathEvaluator;
    FUseWhenDefs: TObjectList;
    FUseWhenFunctions: TList;
    FUseWhenTrue, FUseWhenFalse: TLandrixXmlXPathExpression;
    { the module whose use-when is evaluated (static-base-uri()) }
    FUseWhenModule: TModule;
    { the URIs of the modules being included or imported (a cycle) }
    FChain: TStringList;
    { the namespace URIs of variable names, with the prefix the static
      contexts bind them to }
    FVarUris: TStringList;
    FInternalCall: Boolean;
    { IsPatternNode: the branch was compiled with "//" before it }
    FRelativeBranch: Boolean;
    { the pattern has one branch (SplitPattern), and this branch is
      "." alone (IsPatternNode) }
    FSingleBranch: Boolean;
    FDotPattern: Boolean;
    { the xsl:result-document instructions with a literal format, checked
      when every xsl:output is known (Finish) }
    FFormatChecks: TList;
    { the static base URIs xml:base gives (other than the modules' URIs):
      base index FModules.Count + I is FBaseUris[I] }
    FBaseUris: TStringList;
    { the static base URI of the use-when being evaluated }
    FUseWhenBase: TLandrixXmlUtf8;
    { the character maps (Clark name -> TCharMap, owned; the one of the
      highest import precedence) and the uses of them (TMapRef, owned) in
      declaration order }
    FCharMaps: TStringList;
    FMapRefs: TObjectList;
    { xsl:namespace-alias: stylesheet namespace URI -> TNamespaceAlias
      (owned; the one of the highest import precedence) }
    FAliases: TStringList;
    { the xsl:iterate instructions being compiled, innermost last (the
      parameters xsl:next-iteration sets) }
    FIterates: TList;
    { the xsl:mode declarations (TDecl, not owned) }
    FModeDecls: TList;
    FOutputSeen: TObjectList;
    function VarName(const Clark: TLandrixXmlUtf8): TLandrixXmlUtf8;
    function ModeName(M: TModule; E: Integer; const Value: TLandrixXmlUtf8): TLandrixXmlUtf8;
    function DefaultModeOf(M: TModule; E: Integer): TLandrixXmlUtf8;
    function ModeDeclValue(D: TDecl; const Local: TLandrixXmlUtf8; out Value: TLandrixXmlUtf8): Boolean;
    procedure CompileModes;
    procedure CheckStandard(M: TModule; E: Integer; Data: Boolean);
    procedure CheckExcludedPrefixes(M: TModule; E: Integer; const V: TLandrixXmlUtf8);
    procedure CheckModule(M: TModule);
    procedure PruneUseWhen(M: TModule);
    function HasXmlBase(M: TModule; E: Integer): Boolean;
    function StaticBase(M: TModule; E: Integer): TLandrixXmlUtf8;
    function BaseIndex(M: TModule; E: Integer): Integer;
    function XPathDefaultNamespace(M: TModule; E: Integer): TLandrixXmlUtf8;
    function UseWhen(M: TModule; E: Integer; const Text: TLandrixXmlUtf8): Boolean;
    function UseWhenHost(Evaluator: TLandrixXmlXPathEvaluator; Def: TLandrixXmlXPathFunctionDef;
      const Args: array of TLandrixXmlXPathSequence; const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
    procedure LoadIncludes(M: TModule);
    procedure ProcessImports(M: TModule);
    procedure CollectDecls(M: TModule; Precedence: Integer);
    procedure AddModuleFunctions;
    procedure Fail(M: TModule; E: Integer; const Code, Msg: string);
    procedure Unsupported(M: TModule; E: Integer; const Msg: string);
    procedure CheckDefaultCollation(M: TModule; E: Integer; const V: TLandrixXmlUtf8);
    function ExpandText(M: TModule; E: Integer): Boolean;
    procedure CompileText(M: TModule; E: Integer; Instr: TXsltInstr; Scope: TScope);
    function NoEscape(M: TModule; E: Integer): Boolean;
    procedure XPathFailed(M: TModule; E: Integer; X: ELandrixXmlXPathError);
    function IsXsl(M: TModule; E: Integer; const Local: TLandrixXmlUtf8): Boolean;
    function Attr(M: TModule; E: Integer; const Local: TLandrixXmlUtf8; out Value: TLandrixXmlUtf8): Boolean;
    function ReqAttr(M: TModule; E: Integer; const Local: TLandrixXmlUtf8): TLandrixXmlUtf8;
    function QNameToClark(M: TModule; E: Integer; const QName: TLandrixXmlUtf8; UseDefault: Boolean): TLandrixXmlUtf8;
    function DeclName(M: TModule; E: Integer; const QName: TLandrixXmlUtf8): TLandrixXmlUtf8;
    function LoadModule(M: TModule; E: Integer; const Href: TLandrixXmlUtf8): TModule;
    procedure Collect(M: TModule);
    function NewContext(M: TModule; E: Integer; Scope: TScope): TLandrixXmlXPathStaticContext;
    function Compile(M: TModule; E: Integer; const Text: TLandrixXmlUtf8; Scope: TScope): TLandrixXmlXPathExpression;
    function CompileAttr(M: TModule; E: Integer; const Local: TLandrixXmlUtf8; Scope: TScope): TLandrixXmlXPathExpression;
    function CompileAvt(M: TModule; E: Integer; const Text: TLandrixXmlUtf8; Scope: TScope): TXsltAvt;
    function ParseType(M: TModule; E: Integer; Scope: TScope; out T: TLandrixXmlXPathSequenceType): Boolean;
    function NewInstr(Kind: TXsltInstrKind; M: TModule; E: Integer): TXsltInstr;
    procedure CompileBody(M: TModule; Parent: Integer; Scope: TScope; Body: TObjectList; First: Integer);
    function CompileInstr(M: TModule; E: Integer; Scope: TScope): TXsltInstr;
    function CompileLiteral(M: TModule; E: Integer; Scope: TScope): TXsltInstr;
    function CompileExtension(M: TModule; E: Integer; Scope: TScope; CheckOthers: Boolean): TXsltInstr;
    function YesNoAttr(M: TModule; E: Integer; const Local: TLandrixXmlUtf8): Boolean;
    procedure CompileWithParams(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
    function CompileResultDocument(M: TModule; E: Integer; Scope: TScope): TXsltInstr;
    procedure CompileSortKey(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
    procedure CompileSpace(D: TDecl; Strip: Boolean);
    procedure CompileAnalyzeString(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
    function CompileSorts(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr): Integer;
    function SortFollows(M: TModule; C: Integer): Boolean;
    function CompileVariable(M: TModule; E: Integer; Scope: TScope; Param: Boolean): TXsltInstr;
    procedure CheckSelectOnly(M: TModule; E: Integer; const Code: string);
    procedure CompileIterate(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
    procedure CheckTail(M: TModule; E: Integer);
    procedure CompileNextIteration(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
    procedure CompileGlobals;
    procedure CompileTemplate(D: TDecl);
    function IsPatternNode(X: TLandrixXmlXPathExpression; Index: Integer; First: Boolean): Boolean;
    function PatternBranch(M: TModule; E: Integer; const Branch: TLandrixXmlUtf8; Scope: TScope;
      out Relative: Boolean): TLandrixXmlXPathExpression;
    procedure CompileNumber(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
    procedure CompileGroup(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
    procedure CompileKey(D: TDecl);
    procedure CompileDecimalFormat(D: TDecl);
    procedure CollectFunctions;
    procedure CompileFunction(T: TXsltTemplate; D: TDecl);
    procedure AddRules(D: TDecl; T: TXsltTemplate; const Match: TLandrixXmlUtf8; const Modes: TLandrixXmlUtf8;
      HasModes: Boolean);
    function ModeOf(const Name: TLandrixXmlUtf8): TXsltMode;
    procedure CompileOutput(D: TDecl);
    procedure OutputSeen(D: TDecl; const Key, Value: TLandrixXmlUtf8);
    procedure CheckRoot(M: TModule);
    procedure CompileSimplified(D: TDecl);
    function UseAttributeSets(M: TModule; E: Integer; const Names: TLandrixXmlUtf8): TXsltInstr;
    procedure CompileAttributeSet(D: TDecl);
    function MapNames(M: TModule; E: Integer; const Names: TLandrixXmlUtf8): TLandrixXmlUtf8Array;
    procedure AddMapRef(Props: TXsltOutputProperties; M: TModule; E: Integer; const Names: TLandrixXmlUtf8);
    procedure CompileCharacterMap(D: TDecl);
    procedure KeepMapNames(Map: TCharMap);
    procedure ComposeMap(Map: TCharMap; Props: TXsltOutputProperties);
    procedure FinishCharacterMaps;
    procedure CompileNamespaceAlias(D: TDecl);
    procedure ApplyAlias(Instr: TXsltInstr);
    procedure Finish;
  public
    constructor Create(Resolver: TLandrixXmlXsltResolver);
    destructor Destroy; override;
    function Run(Tree: TLandrixXmlXPathTree; const BaseUri: TLandrixXmlUtf8): TXsltCompiled;
  end;

destructor TModule.Destroy;
begin
  if Owned then
    Tree.Free;
  inherited Destroy;
end;

function TModule.LineOf(E: Integer): Integer;
begin
  if (E >= 0) and (E < Length(Lines)) then
    Result := Lines[E]
  else
    Result := Tree.Line[E];
end;

function TModule.ColumnOf(E: Integer): Integer;
begin
  if (E >= 0) and (E < Length(Columns)) then
    Result := Columns[E]
  else
    Result := Tree.Column[E];
end;

function TModule.IncludedAt(E: Integer): TModule;
var
  I: Integer;
begin
  for I := 0 to Integer(Length(IncludeElements)) - 1 do
    if IncludeElements[I] = E then
    begin
      Result := IncludeModules[I];
      Exit;
    end;
  Result := nil;
end;

procedure TScope.Add(const Lexical, Clark: TLandrixXmlUtf8; Slot: Integer);
begin
  if Count = Length(Names) then
  begin
    SetLength(Names, 2 * Count + 8);
    SetLength(Clarks, 2 * Count + 8);
    SetLength(Slots, 2 * Count + 8);
  end;
  Names[Count] := Lexical;
  Clarks[Count] := Clark;
  Slots[Count] := Slot;
  Inc(Count);
end;

constructor TCompiler.Create(Resolver: TLandrixXmlXsltResolver);
begin
  inherited Create;
  FResolver := Resolver;
  if FResolver = nil then
  begin
    FResolver := TLandrixXmlXsltResolver.Create;
    FOwnResolver := True;
  end;
  FModules := TObjectList.Create;
  FDecls := TObjectList.Create;
  FFunctionDecls := TList.Create;
  FAllModeTemplates := TList.Create;
  FDupTemplates := TList.Create;
  FDupTemplateDecls := TList.Create;
  FChain := TXsltStringList.Create;
  FChain.CaseSensitive := True;
  FVarUris := TXsltStringList.Create;
  FVarUris.CaseSensitive := True;
  FFormatChecks := TList.Create;
  FBaseUris := TXsltStringList.Create;
  FBaseUris.CaseSensitive := True;
  FCharMaps := TXsltStringList.Create;
  FCharMaps.CaseSensitive := True;
  FCharMaps.Sorted := True;
  FMapRefs := TObjectList.Create;
  FAliases := TXsltStringList.Create;
  FAliases.CaseSensitive := True;
  FAliases.Sorted := True;
  FIterates := TList.Create;
  FModeDecls := TList.Create;
  FOutputSeen := TObjectList.Create;
end;

destructor TCompiler.Destroy;
var
  I: Integer;
begin
  for I := 0 to Integer(FCharMaps.Count) - 1 do
    FCharMaps.Objects[I].Free;
  FCharMaps.Free;
  FMapRefs.Free;
  for I := 0 to Integer(FAliases.Count) - 1 do
    FAliases.Objects[I].Free;
  FAliases.Free;
  FIterates.Free;
  FModeDecls.Free;
  FOutputSeen.Free;
  FUseWhenTrue.Free;
  FUseWhenFalse.Free;
  FUseWhenEvaluator.Free;
  FUseWhenFunctions.Free;
  FUseWhenDefs.Free;
  FUseWhenTree.Free;
  FFormatChecks.Free;
  FBaseUris.Free;
  FVarUris.Free;
  FChain.Free;
  FAllModeTemplates.Free;
  FDupTemplates.Free;
  FDupTemplateDecls.Free;
  FFunctionDecls.Free;
  FDecls.Free;
  FModules.Free;
  if FOwnResolver then
    FResolver.Free;
  inherited Destroy;
end;

procedure TCompiler.Fail(M: TModule; E: Integer; const Code, Msg: string);
var
  Line, Column: Integer;
begin
  Line := 0;
  Column := 0;
  if (M <> nil) and (E >= 0) then
  begin
    Line := M.LineOf(E);
    Column := M.ColumnOf(E);
  end;
  if M <> nil then
    raise ELandrixXmlXsltError.CreateXslt(xecXslt, Code, Msg, M.Uri, Line, Column)
  else
    raise ELandrixXmlXsltError.CreateXslt(xecXslt, Code, Msg, '', 0, 0);
end;

procedure TCompiler.Unsupported(M: TModule; E: Integer; const Msg: string);
begin
  raise ELandrixXmlXsltError.CreateXslt(xecUnsupported, 'FOER0000', Msg + ' is not supported', M.Uri,
    M.LineOf(E), M.ColumnOf(E));
end;

{ [xsl:]default-collation: the first URI of the list (resolved against
  the static base URI) that is recognized as a collation is the default
  collation (XTSE0125 if there is none); only the codepoint collation is
  supported }
procedure TCompiler.CheckDefaultCollation(M: TModule; E: Integer; const V: TLandrixXmlUtf8);
var
  K, Start: Integer;
  W, S: TLandrixXmlUtf8;
begin
  S := V + ' ';
  Start := 1;
  for K := 1 to Length(S) do
    if S[K] in [#9, #10, #13, ' '] then
    begin
      W := Copy(S, Start, K - Start);
      Start := K + 1;
      if W = '' then
        Continue;
      case XsltCollationKind(LandrixXmlXPathResolveUri(W, StaticBase(M, E))) of
        0:
          Exit;
        1:
          Unsupported(M, E, 'default-collation="' + LandrixXmlUtf8ToString(W) + '"');
      end;
    end;
  Fail(M, E, 'XTSE0125', 'default-collation names no known collation: "' +
    LandrixXmlUtf8ToString(V) + '"');
end;

{ an XPath error of an expression at E, as an XSLT error with E's position }
procedure TCompiler.XPathFailed(M: TModule; E: Integer; X: ELandrixXmlXPathError);
var
  Code: TLandrixXmlErrorCode;
begin
  { a limit of the parser stays a limit }
  if X.Code = xecLimit then
    Code := xecLimit
  else
    Code := xecXPath;
  raise ELandrixXmlXsltError.CreateXslt(Code, X.XPathCode, Copy(X.Message, Length(X.XPathCode) + 3, MaxInt),
    M.Uri, M.LineOf(E), M.ColumnOf(E));
end;

function TCompiler.IsXsl(M: TModule; E: Integer; const Local: TLandrixXmlUtf8): Boolean;
begin
  Result := (M.Tree.Kind[E] = xnkElement) and (M.Tree.NamespaceUriUtf8(E) = XsltNamespace) and
    ((Local = '') or (M.Tree.LocalNameUtf8(E) = Local));
end;

function TCompiler.Attr(M: TModule; E: Integer; const Local: TLandrixXmlUtf8; out Value: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := E + 1 to E + M.Tree.AttributeCount[E] do
    if (M.Tree.NamespaceUriUtf8(I) = '') and (M.Tree.LocalNameUtf8(I) = Local) then
    begin
      Value := M.Tree.ValueUtf8(I);
      Exit;
    end;
  Value := '';
  Result := False;
end;

function TCompiler.ReqAttr(M: TModule; E: Integer; const Local: TLandrixXmlUtf8): TLandrixXmlUtf8;
begin
  if not Attr(M, E, Local, Result) then
    Fail(M, E, 'XTSE0010', 'xsl:' + LandrixXmlUtf8ToString(M.Tree.LocalNameUtf8(E)) + ' needs the attribute ' +
      LandrixXmlUtf8ToString(Local));
end;

function Trim8(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  A, B: Integer;
begin
  A := 1;
  B := Length(S);
  while (A <= B) and (S[A] in [#9, #10, #13, ' ']) do
    Inc(A);
  while (B >= A) and (S[B] in [#9, #10, #13, ' ']) do
    Dec(B);
  Result := Copy(S, A, B - A + 1);
end;

{ S with its white space collapsed: runs of tab, line feed, carriage
  return and space one space, none at the ends }
function Collapse8(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I, N: Integer;
  Space: Boolean;
begin
  Result := '';
  SetLength(Result, Length(S));
  N := 0;
  Space := False;
  for I := 1 to Length(S) do
    if S[I] in [#9, #10, #13, ' '] then
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

{ the namespaces reserved for XSLT, XPath, XML Schema and XML (XTSE0080) }
function ReservedNamespace(const Uri: TLandrixXmlUtf8): Boolean;
begin
  Result := (Uri = XsltNamespace) or (Uri = LandrixXmlNamespaceXml) or (Uri = 'http://www.w3.org/2001/XMLSchema') or
    (Uri = 'http://www.w3.org/2001/XMLSchema-instance') or (Uri = 'http://www.w3.org/2005/xqt-errors') or
    (Uri = LandrixXmlXPathFunctionNamespace) or (Uri = 'http://www.w3.org/2005/xpath-functions/math') or
    (Uri = 'http://www.w3.org/2005/xpath-functions/map') or (Uri = 'http://www.w3.org/2005/xpath-functions/array') or
    (Uri = 'http://www.w3.org/2000/xmlns/');
end;

{ disable-output-escaping of xsl:text and xsl:value-of: yes or no (as
  Saxon also true, 1, false and 0; XTSE0020 otherwise) }
function TCompiler.NoEscape(M: TModule; E: Integer): Boolean;
var
  V: TLandrixXmlUtf8;
begin
  Result := False;
  if not Attr(M, E, 'disable-output-escaping', V) then
    Exit;
  V := Trim8(V);
  if (V = 'yes') or (V = 'true') or (V = '1') then
    Result := True
  else if (V <> 'no') and (V <> 'false') and (V <> '0') then
    Fail(M, E, 'XTSE0020', 'disable-output-escaping is yes or no');
end;

function IsNCName8(const S: TLandrixXmlUtf8): Boolean; forward;

function TCompiler.QNameToClark(M: TModule; E: Integer; const QName: TLandrixXmlUtf8;
  UseDefault: Boolean): TLandrixXmlUtf8;
var
  I: Integer;
  Prefix, Local, Uri, Q: TLandrixXmlUtf8;
begin
  Q := Trim8(QName);
  I := Pos8(':', Q);
  { the lexical form first: a malformed name is XTSE0020 before its prefix
    is looked up (XTSE0280), as with Saxon }
  if I > 0 then
  begin
    Prefix := Copy(Q, 1, I - 1);
    Local := Copy(Q, I + 1, Length(Q) - I);
  end
  else
  begin
    Prefix := '';
    Local := Q;
  end;
  if not IsNCName8(Local) or (I > 0) and not IsNCName8(Prefix) then
    Fail(M, E, 'XTSE0020', 'not a QName: "' + LandrixXmlUtf8ToString(QName) + '"');
  if I > 0 then
  begin
    if not M.Tree.LookupNamespace(E, Prefix, Uri) then
      Fail(M, E, 'XTSE0280', 'the prefix ' + LandrixXmlUtf8ToString(Prefix) + ' is not declared');
  end
  else
  begin
    Uri := '';
    if UseDefault then
      M.Tree.LookupNamespace(E, '', Uri);
  end;
  Result := XsltClarkOf(Uri, Local);
end;

{ the Clark name of a declared object (a template, variable, parameter,
  key, attribute set, character map or output definition): XTSE0080 in a
  reserved namespace (but for the template xsl:initial-template of XSLT
  3.0) }
function TCompiler.DeclName(M: TModule; E: Integer; const QName: TLandrixXmlUtf8): TLandrixXmlUtf8;
begin
  Result := QNameToClark(M, E, QName, False);
  if (Result = XsltClarkOf(XsltNamespace, 'initial-template')) and IsXsl(M, E, 'template') then
    Exit;
  if (Copy(Result, 1, 1) = '{') and ReservedNamespace(Copy(Result, 2, Pos8('}', Result) - 2)) then
    Fail(M, E, 'XTSE0080', 'the name "' + LandrixXmlUtf8ToString(Trim8(QName)) + '" is in a reserved namespace');
end;

{ --- modules and declarations ------------------------------------------------ }

function TCompiler.LoadModule(M: TModule; E: Integer; const Href: TLandrixXmlUtf8): TModule;
var
  Uri: TLandrixXmlUtf8;
  Content: TStream;
  Reader: TLandrixXmlReader;
  I: Integer;
begin
  Content := nil;
  if not FResolver.Resolve(xrkStylesheet, StaticBase(M, E), Href, Uri, Content) then
    Fail(M, E, 'XTSE0165', 'the stylesheet module ' + LandrixXmlUtf8ToString(Href) + ' cannot be read');
  try
    { a cycle: the module is being included or imported already (the same
      module imported twice elsewhere is no cycle); closed by an xsl:import
      XTSE0210, by an xsl:include XTSE0180 }
    for I := 0 to Integer(FChain.Count) - 1 do
      if FChain[I] = LandrixXmlUtf8ToKey(Uri) then
      begin
        if IsXsl(M, E, 'import') then
          Fail(M, E, 'XTSE0210', 'the module ' + LandrixXmlUtf8ToString(Uri) + ' imports itself');
        Fail(M, E, 'XTSE0180', 'the module ' + LandrixXmlUtf8ToString(Uri) + ' includes itself');
      end;
    Result := TModule.Create;
    Result.Tree := TLandrixXmlXPathTree.Create;
    Result.Owned := True;
    Result.Uri := Uri;
    Result.Index := Integer(FModules.Count);
    FModules.Add(Result);
    Reader := TLandrixXmlReader.Create;
    try
      try
        Reader.LoadFromStream(Content);
        Result.Tree.LoadFromReader(Reader);
      except
        on X: ELandrixXmlXsltError do
          raise;
        on X: ELandrixXmlError do
          Fail(M, E, 'XTSE0165', 'the stylesheet module ' + LandrixXmlUtf8ToString(Uri) + ' is not well-formed: ' +
            X.Message);
      end;
    finally
      Reader.Free;
    end;
    Result.Tree.BaseUri := Uri;
  finally
    Content.Free;
  end;
  CheckRoot(Result);
  CheckModule(Result);
end;

{ Reads the modules M includes, recursively (the chain: a cycle). }
procedure TCompiler.LoadIncludes(M: TModule);
var
  E, C, N: Integer;
  Inc: TModule;
begin
  FChain.Add(LandrixXmlUtf8ToKey(M.Uri));
  try
    E := M.Tree.DocumentElement;
    C := -1;
    if not M.Simplified then
      C := M.Tree.FirstChild(E);
    while C >= 0 do
    begin
      if IsXsl(M, C, 'include') then
      begin
        Inc := LoadModule(M, C, ReqAttr(M, C, 'href'));
        N := Integer(Length(M.IncludeElements));
        SetLength(M.IncludeElements, N + 1);
        SetLength(M.IncludeModules, N + 1);
        M.IncludeElements[N] := C;
        M.IncludeModules[N] := Inc;
        LoadIncludes(Inc);
      end;
      C := M.Tree.NextSibling[C];
    end;
  finally
    FChain.Delete(FChain.Count - 1);
  end;
end;

{ The imports of M and of the modules it includes, in declaration order
  (those of an included module at the position of its xsl:include): lower
  precedence, the later import the higher. }
procedure TCompiler.ProcessImports(M: TModule);
var
  E, C: Integer;
begin
  FChain.Add(LandrixXmlUtf8ToKey(M.Uri));
  try
    E := M.Tree.DocumentElement;
    C := -1;
    if not M.Simplified then
      C := M.Tree.FirstChild(E);
    while C >= 0 do
    begin
      if IsXsl(M, C, 'import') then
        Collect(LoadModule(M, C, ReqAttr(M, C, 'href')))
      else if IsXsl(M, C, 'include') then
        ProcessImports(M.IncludedAt(C));
      C := M.Tree.NextSibling[C];
    end;
  finally
    FChain.Delete(FChain.Count - 1);
  end;
end;

{ The declarations of M in document order, those of an included module at
  the position of its xsl:include. }
procedure TCompiler.CollectDecls(M: TModule; Precedence: Integer);
var
  E, C: Integer;
  D: TDecl;
begin
  E := M.Tree.DocumentElement;
  if M.Simplified then
  begin
    D := TDecl.Create;
    D.Module := M;
    D.Element := E;
    D.Precedence := Precedence;
    D.Order := FNextOrder;
    D.Simplified := True;
    Inc(FNextOrder);
    FDecls.Add(D);
    Exit;
  end;
  C := M.Tree.FirstChild(E);
  while C >= 0 do
  begin
    if M.Tree.Kind[C] = xnkElement then
    begin
      if IsXsl(M, C, 'include') then
        CollectDecls(M.IncludedAt(C), Precedence)
      else if not IsXsl(M, C, 'import') then
      begin
        D := TDecl.Create;
        D.Module := M;
        D.Element := C;
        D.Precedence := Precedence;
        D.Order := FNextOrder;
        Inc(FNextOrder);
        FDecls.Add(D);
      end;
    end
    else if (M.Tree.Kind[C] = xnkText) and (Trim8(M.Tree.ValueUtf8(C)) <> '') then
      Fail(M, E, 'XTSE0120', 'text at the top level of a stylesheet');
    C := M.Tree.NextSibling[C];
  end;
end;

{ Imports first (lower precedence), then the declarations of M and its
  includes with the next precedence. }
procedure TCompiler.Collect(M: TModule);
var
  P, Low: Integer;
begin
  LoadIncludes(M);
  Low := FNextPrecedence;
  ProcessImports(M);
  P := FNextPrecedence;
  Inc(FNextPrecedence);
  if Length(FC.ImportLow) <= P then
    SetLength(FC.ImportLow, P + 1);
  FC.ImportLow[P] := Low;
  CollectDecls(M, P);
end;

{ the class of a version attribute (an xs:decimal): -1 not a decimal,
  0 below 2.0 (backwards compatible processing), 1 from 2.0 to 3.0, 2
  above 3.0 (forwards compatible processing, as for Saxon, an XSLT 3.0
  processor) }
function VersionClass(const Value: TLandrixXmlUtf8): Integer;
var
  S, IntPart, Frac: TLandrixXmlUtf8;
  I, Dot: Integer;
  Negative: Boolean;
begin
  Result := -1;
  S := Trim8(Value);
  Negative := False;
  if (S <> '') and ((S[1] = '+') or (S[1] = '-')) then
  begin
    Negative := S[1] = '-';
    Delete(S, 1, 1);
  end;
  Dot := 0;
  for I := 1 to Length(S) do
    if S[I] = '.' then
    begin
      if Dot > 0 then
        Exit;
      Dot := I;
    end
    else if not (S[I] in ['0'..'9']) then
      Exit;
  if (S = '') or (S = '.') then
    Exit;
  if Dot > 0 then
  begin
    IntPart := Copy(S, 1, Dot - 1);
    Frac := Copy(S, Dot + 1, MaxInt);
  end
  else
  begin
    IntPart := S;
    Frac := '';
  end;
  while (IntPart <> '') and (IntPart[1] = '0') do
    Delete(IntPart, 1, 1);
  while (Frac <> '') and (Frac[Length(Frac)] = '0') do
    Delete(Frac, Length(Frac), 1);
  if Negative or (IntPart = '') or (Length(IntPart) = 1) and (IntPart[1] < '2') then
    Result := 0
  else if (IntPart = '2') or (IntPart = '3') and (Frac = '') then
    Result := 1
  else
    Result := 2;
end;

{ the class of the version E is processed with (see VersionClass; 1 for
  none): the nearest version (version on an XSLT element, but the output
  version of xsl:output; xsl:version on another element) }
function VersionAt(M: TModule; E: Integer): Integer;
var
  N, K: Integer;
  Xsl: Boolean;
begin
  Result := 1;
  N := E;
  while N >= 0 do
  begin
    if M.Tree.Kind[N] = xnkElement then
    begin
      Xsl := M.Tree.NamespaceUriUtf8(N) = XsltNamespace;
      if not (Xsl and (M.Tree.LocalNameUtf8(N) = 'output')) then
        for K := N + 1 to N + M.Tree.AttributeCount[N] do
          if (M.Tree.LocalNameUtf8(K) = 'version') and
            (Xsl and (M.Tree.NamespaceUriUtf8(K) = '') or not Xsl and (M.Tree.NamespaceUriUtf8(K) = XsltNamespace)) then
          begin
            Result := VersionClass(M.Tree.ValueUtf8(K));
            Exit;
          end;
    end;
    N := M.Tree.Parent[N];
  end;
end;

{ whether E is processed in forwards compatible mode (a version above
  3.0) }
function Forwards(M: TModule; E: Integer): Boolean;
begin
  Result := VersionAt(M, E) = 2;
end;

{ whether E is processed in backwards compatible mode (a version below
  2.0): its expressions in XPath 1.0 compatibility mode }
function Backwards(M: TModule; E: Integer): Boolean;
begin
  Result := VersionAt(M, E) = 0;
end;

{ a top-level element in the XSLT namespace that is no declaration XSLT
  3.0 knows, in forwards compatible mode: ignored with its content }
function IgnoredDeclaration(M: TModule; E: Integer): Boolean;
const
  Known = ' template output attribute-set character-map namespace-alias key decimal-format strip-space ' +
    'preserve-space variable param import include function import-schema mode accumulator use-package ' +
    'global-context-item stylesheet transform ';
begin
  Result := (M.Tree.NamespaceUriUtf8(E) = XsltNamespace) and (M.Tree.Parent[E] >= 0) and
    (M.Tree.Parent[E] = M.Tree.DocumentElement) and
    (Pos(' ' + LandrixXmlUtf8ToString(M.Tree.LocalNameUtf8(E)) + ' ', Known) = 0) and Forwards(M, E);
end;

{ the first prefix of extension-element-prefixes that is not declared
  (#default always is: Saxon takes it for no namespace; #all is a prefix
  that is not declared, as in Saxon), or '#' and the first one bound to a
  reserved namespace; '' if none }
function BadExtensionPrefix(M: TModule; E: Integer; const V: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  K, Start: Integer;
  W, U, S: TLandrixXmlUtf8;
begin
  Result := '';
  S := V + ' ';
  Start := 1;
  for K := 1 to Length(S) do
    if S[K] in [#9, #10, #13, ' '] then
    begin
      W := Copy(S, Start, K - Start);
      Start := K + 1;
      if (W = '') or (W = '#default') then
        Continue;
      if not M.Tree.LookupNamespace(E, W, U) then
      begin
        Result := W;
        Exit;
      end;
      { a reserved namespace (Saxon: XTSE0085) }
      if ReservedNamespace(U) then
      begin
        Result := '#' + W;
        Exit;
      end;
    end;
end;

{ whether the element E of the stylesheet is in an extension namespace:
  one extension-element-prefixes of E or an ancestor names (on an XSLT
  element without, on another with the XSLT namespace); #default is no
  namespace, as in Saxon }
function IsExtension(M: TModule; E: Integer): Boolean;
var
  N, K, J, Start: Integer;
  Uri, V, W, U: TLandrixXmlUtf8;
  Xsl: Boolean;
begin
  Result := False;
  Uri := M.Tree.NamespaceUriUtf8(E);
  if Uri = XsltNamespace then
    Exit;
  N := E;
  while N >= 0 do
  begin
    if M.Tree.Kind[N] = xnkElement then
    begin
      Xsl := M.Tree.NamespaceUriUtf8(N) = XsltNamespace;
      for K := N + 1 to N + M.Tree.AttributeCount[N] do
        if (M.Tree.LocalNameUtf8(K) = 'extension-element-prefixes') and
          (Xsl and (M.Tree.NamespaceUriUtf8(K) = '') or not Xsl and (M.Tree.NamespaceUriUtf8(K) = XsltNamespace)) then
        begin
          V := M.Tree.ValueUtf8(K) + ' ';
          Start := 1;
          for J := 1 to Length(V) do
            if V[J] in [#9, #10, #13, ' '] then
            begin
              W := Copy(V, Start, J - Start);
              Start := J + 1;
              if W = '' then
                Continue;
              if W = '#default' then
                U := ''
              else if not M.Tree.LookupNamespace(N, W, U) then
                Continue;
              if U = Uri then
              begin
                Result := True;
                Exit;
              end;
            end;
        end;
    end;
    N := M.Tree.Parent[N];
  end;
end;

{ The attributes without namespace that XSLT element Local may have
  besides the standard ones, between spaces (XSLT 3.0, as Saxon runs
  XSLT 2.0 stylesheets); False for an element not checked here (unknown,
  or checked where it is compiled: xsl:output, xsl:result-document). }
function XsltElementAttributes(const Local: TLandrixXmlUtf8; out List: TLandrixXmlUtf8): Boolean;
begin
  Result := True;
  if Local = 'analyze-string' then
    List := ' select regex flags '
  else if (Local = 'apply-imports') or (Local = 'choose') or (Local = 'fallback') or
    (Local = 'matching-substring') or (Local = 'non-matching-substring') or (Local = 'next-match') or
    (Local = 'otherwise') then
    List := ' '
  else if Local = 'apply-templates' then
    List := ' select mode '
  else if Local = 'attribute' then
    List := ' name namespace select separator type validation '
  else if Local = 'attribute-set' then
    List := ' name use-attribute-sets visibility streamable '
  else if Local = 'call-template' then
    List := ' name '
  else if Local = 'character-map' then
    List := ' name use-character-maps '
  else if Local = 'comment' then
    List := ' select '
  else if Local = 'copy' then
    List := ' select copy-namespaces inherit-namespaces use-attribute-sets type validation '
  else if Local = 'copy-of' then
    List := ' select copy-accumulators copy-namespaces type validation '
  else if Local = 'decimal-format' then
    List := ' name decimal-separator grouping-separator infinity minus-sign exponent-separator NaN percent ' +
      'per-mille zero-digit digit pattern-separator '
  else if Local = 'document' then
    List := ' validation type '
  else if Local = 'element' then
    List := ' name namespace inherit-namespaces use-attribute-sets type validation '
  else if Local = 'for-each' then
    List := ' select '
  else if Local = 'for-each-group' then
    List := ' select group-by group-adjacent group-starting-with group-ending-with composite collation '
  else if Local = 'function' then
    List := ' name as visibility streamability override-extension-function override new-each-time cache '
  else if (Local = 'if') or (Local = 'when') then
    List := ' test '
  else if (Local = 'import') or (Local = 'include') then
    List := ' href '
  else if Local = 'import-schema' then
    List := ' namespace schema-location '
  else if (Local = 'iterate') or (Local = 'break') or (Local = 'on-completion') then
    List := ' select '
  else if Local = 'next-iteration' then
    List := ' '
  else if Local = 'key' then
    List := ' name match use composite collation '
  else if Local = 'message' then
    List := ' select terminate error-code '
  else if Local = 'mode' then
    List := ' name streamable use-accumulators on-no-match on-multiple-match warning-on-no-match ' +
      'warning-on-multiple-match typed visibility '
  else if Local = 'namespace' then
    List := ' name select '
  else if Local = 'namespace-alias' then
    List := ' stylesheet-prefix result-prefix '
  else if Local = 'number' then
    List := ' value select level count from format lang letter-value ordinal start-at grouping-separator ' +
      'grouping-size '
  else if Local = 'output-character' then
    List := ' character string '
  else if Local = 'param' then
    List := ' name select as required tunnel static '
  else if Local = 'perform-sort' then
    List := ' select '
  else if (Local = 'preserve-space') or (Local = 'strip-space') then
    List := ' elements '
  else if Local = 'processing-instruction' then
    List := ' name select '
  else if Local = 'sequence' then
    List := ' select '
  else if Local = 'sort' then
    List := ' select lang order collation stable case-order data-type '
  else if (Local = 'stylesheet') or (Local = 'transform') then
    List := ' id input-type-annotations package-version '
  else if Local = 'template' then
    List := ' match name priority mode as visibility '
  else if Local = 'text' then
    List := ' disable-output-escaping '
  else if Local = 'value-of' then
    List := ' select separator disable-output-escaping '
  else if Local = 'variable' then
    List := ' name select as static visibility '
  else if Local = 'with-param' then
    List := ' name select as tunnel '
  else
  begin
    List := '';
    Result := False;
  end;
end;

{ the standard attributes: without namespace on an XSLT element, in the
  XSLT namespace on a literal result element (with the four of literal
  result elements) }
function IsStandardAttribute(const L: TLandrixXmlUtf8; Literal: Boolean): Boolean;
begin
  Result := (L = 'version') or (L = 'exclude-result-prefixes') or (L = 'extension-element-prefixes') or
    (L = 'xpath-default-namespace') or (L = 'default-collation') or (L = 'default-mode') or
    (L = 'default-validation') or (L = 'expand-text') or (L = 'use-when') or
    Literal and ((L = 'use-attribute-sets') or (L = 'type') or (L = 'validation') or
    (L = 'inherit-namespaces'));
end;

{ exclude-result-prefixes: #all alone (XTSE0020), every prefix declared
  (XTSE0808), #default only with a default namespace (XTSE0809) }
procedure TCompiler.CheckExcludedPrefixes(M: TModule; E: Integer; const V: TLandrixXmlUtf8);
var
  K, Start, Count: Integer;
  S, W, U: TLandrixXmlUtf8;
  All: Boolean;
begin
  S := V + ' ';
  Start := 1;
  Count := 0;
  All := False;
  for K := 1 to Length(S) do
    if S[K] in [#9, #10, #13, ' '] then
    begin
      if K > Start then
        Inc(Count);
      if Copy(S, Start, K - Start) = '#all' then
        All := True;
      Start := K + 1;
    end;
  if All and (Count > 1) then
    Fail(M, E, 'XTSE0020', 'exclude-result-prefixes="#all" cannot be combined with other prefixes');
  Start := 1;
  for K := 1 to Length(S) do
    if S[K] in [#9, #10, #13, ' '] then
    begin
      W := Copy(S, Start, K - Start);
      Start := K + 1;
      if (W = '') or (W = '#all') then
        Continue;
      if W = '#default' then
      begin
        if not M.Tree.LookupNamespace(E, '', U) or (U = '') then
          Fail(M, E, 'XTSE0809', 'exclude-result-prefixes names #default without a default namespace');
      end
      else if not M.Tree.LookupNamespace(E, W, U) or (U = '') then
        Fail(M, E, 'XTSE0808', 'the prefix ' + LandrixXmlUtf8ToString(W) + ' of exclude-result-prefixes ' +
          'is not declared');
    end;
end;

{ The attributes every XSLT element may have (an XSLT element: E, a
  literal result element: those in the XSLT namespace), rejected if they
  ask for what is not supported. Data: E is in a user-defined data
  element, whose xsl: attributes Saxon does not check against the
  literal result element (neither are those of an extension
  instruction). }
procedure TCompiler.CheckStandard(M: TModule; E: Integer; Data: Boolean);
var
  I: Integer;
  L, V, Bad, Allowed: TLandrixXmlUtf8;
  Xsl, Known: Boolean;
begin
  Xsl := M.Tree.NamespaceUriUtf8(E) = XsltNamespace;
  Allowed := '';
  Known := Xsl and XsltElementAttributes(M.Tree.LocalNameUtf8(E), Allowed);
  for I := E + 1 to E + M.Tree.AttributeCount[E] do
  begin
    if Xsl then
    begin
      if (M.Tree.NamespaceUriUtf8(I) = XsltNamespace) and not Forwards(M, E) then
        Fail(M, E, 'XTSE0090', 'an XSLT element has no attribute in the XSLT namespace (' +
          LandrixXmlUtf8ToString(M.Tree.PrefixUtf8(I)) + ':' + LandrixXmlUtf8ToString(M.Tree.LocalNameUtf8(I)) + ')');
      if M.Tree.NamespaceUriUtf8(I) <> '' then
        Continue;
      L := M.Tree.LocalNameUtf8(I);
      { a shadow attribute (_select: XSLT 3.0 static expressions) }
      if (L <> '') and (L[1] = '_') and not Forwards(M, E) then
        Unsupported(M, E, 'the shadow attribute ' + LandrixXmlUtf8ToString(L) + ' (XSLT 3.0)');
      { an attribute the element does not define (Saxon checks every
        element; forwards compatible processing ignores it) }
      if Known and not IsStandardAttribute(L, False) and (Pos8(' ' + L + ' ', Allowed) = 0) and
        not Forwards(M, E) then
        Fail(M, E, 'XTSE0090', 'xsl:' + LandrixXmlUtf8ToString(M.Tree.LocalNameUtf8(E)) + ' has no attribute ' +
          LandrixXmlUtf8ToString(L));
    end
    else if M.Tree.NamespaceUriUtf8(I) <> XsltNamespace then
      Continue
    else if not Data and not IsStandardAttribute(M.Tree.LocalNameUtf8(I), True) and not Forwards(M, E) and
      not IsExtension(M, E) then
      Fail(M, E, 'XTSE0805', 'a literal result element has no attribute xsl:' +
        LandrixXmlUtf8ToString(M.Tree.LocalNameUtf8(I)));
    L := M.Tree.LocalNameUtf8(I);
    V := Trim8(M.Tree.ValueUtf8(I));
    if L = 'default-collation' then
      CheckDefaultCollation(M, E, V);
    if (L = 'expand-text') and (V <> 'yes') and (V <> 'no') and (V <> 'true') and (V <> 'false') and
      (V <> '1') and (V <> '0') then
      Fail(M, E, 'XTSE0020', 'expand-text="' + LandrixXmlUtf8ToString(V) + '" is neither yes nor no');
    { #unnamed or a mode name (EQName): XTSE0020, XTSE0280 (not in a
      user-defined data element, as in Saxon) }
    if (L = 'default-mode') and (V <> '#unnamed') and not Data then
      { a mode of the stylesheet (with the mode="#all" rules) }
      ModeOf(ModeName(M, E, V));
    if (L = 'default-validation') or (L = 'input-type-annotations') or
      ((L = 'inherit-namespaces') and (V = 'no')) or
      ((L = 'validation') and (V <> 'strip') and (V <> 'preserve')) or (L = 'type') then
      Unsupported(M, E, LandrixXmlUtf8ToString(L) + '="' + LandrixXmlUtf8ToString(V) + '"');
    if L = 'extension-element-prefixes' then
    begin
      Bad := BadExtensionPrefix(M, E, V);
      if Copy(Bad, 1, 1) = '#' then
        Fail(M, E, 'XTSE0085', 'extension-element-prefixes names a reserved namespace (prefix ' +
          LandrixXmlUtf8ToString(Copy(Bad, 2, MaxInt)) + ')')
      else if Bad <> '' then
        Fail(M, E, 'XTSE1430', 'the prefix ' + LandrixXmlUtf8ToString(Bad) + ' of extension-element-prefixes ' +
          'is not declared');
    end;
    { also in forwards compatible processing (Saxon) }
    if (L = 'exclude-result-prefixes') and not Data then
      CheckExcludedPrefixes(M, E, V);
    if (L = 'version') and not (Xsl and IsXsl(M, E, 'output')) then
      case VersionClass(V) of
        -1:
          Fail(M, E, 'XTSE0110', 'the version "' + LandrixXmlUtf8ToString(V) + '" is not a number');
      else
        { below 2.0 backwards compatible, 2.0 and 3.0 by the rules of XSLT
          2.0, above forwards compatible }
      end;
  end;
end;

function PreservesSpace(T: TLandrixXmlXPathTree; N: Integer): Boolean; forward;

{ the default element/type namespace of the XPath expressions of E: the
  [xsl:]xpath-default-namespace of E or of the nearest ancestor that has
  one ('' for none) }
function TCompiler.XPathDefaultNamespace(M: TModule; E: Integer): TLandrixXmlUtf8;
var
  A, I: Integer;
  Xsl: Boolean;
begin
  Result := '';
  A := E;
  while A >= 0 do
  begin
    if M.Tree.Kind[A] = xnkElement then
    begin
      Xsl := M.Tree.NamespaceUriUtf8(A) = XsltNamespace;
      for I := A + 1 to A + M.Tree.AttributeCount[A] do
        if (M.Tree.LocalNameUtf8(I) = 'xpath-default-namespace') and
          ((Xsl and (M.Tree.NamespaceUriUtf8(I) = '')) or
          (not Xsl and (M.Tree.NamespaceUriUtf8(I) = XsltNamespace))) then
        begin
          { an xs:anyURI: white space collapsed (Saxon) }
          Result := Trim8(M.Tree.ValueUtf8(I));
          Exit;
        end;
    end;
    A := M.Tree.Parent[A];
  end;
end;

{ the static base URI of E: the module's URI with the xml:base
  attributes of E and its ancestors applied, outermost first }
function TCompiler.StaticBase(M: TModule; E: Integer): TLandrixXmlUtf8;
var
  Bases: TLandrixXmlUtf8Array;
  A, I, N: Integer;
begin
  Bases := nil;
  N := 0;
  A := E;
  while A >= 0 do
  begin
    if M.Tree.Kind[A] = xnkElement then
      for I := A + 1 to A + M.Tree.AttributeCount[A] do
        if (M.Tree.NamespaceUriUtf8(I) = LandrixXmlNamespaceXml) and (M.Tree.LocalNameUtf8(I) = 'base') then
        begin
          SetLength(Bases, N + 1);
          Bases[N] := M.Tree.ValueUtf8(I);
          Inc(N);
        end;
    A := M.Tree.Parent[A];
  end;
  Result := M.Uri;
  for I := N - 1 downto 0 do
    Result := LandrixXmlXPathResolveUri(Bases[I], Result);
end;

{ the index of the functions with E's static base URI (doc(),
  static-base-uri() and the others): the module's, or one xml:base gives
  (registered by AddModuleFunctions) }
function TCompiler.BaseIndex(M: TModule; E: Integer): Integer;
var
  B: TLandrixXmlUtf8;
begin
  Result := M.Index;
  if E < 0 then
    Exit;
  B := StaticBase(M, E);
  if B = M.Uri then
    Exit;
  Result := FBaseUris.IndexOf(LandrixXmlUtf8ToKey(B));
  if Result < 0 then
    Result := M.Index
  else
    Inc(Result, FModules.Count);
end;

function TCompiler.HasXmlBase(M: TModule; E: Integer): Boolean;
var
  A: Integer;
begin
  Result := True;
  for A := E + 1 to E + M.Tree.AttributeCount[E] do
    if (M.Tree.NamespaceUriUtf8(A) = LandrixXmlNamespaceXml) and (M.Tree.LocalNameUtf8(A) = 'base') then
      Exit;
  Result := False;
end;

{ S as an XPath string literal }
function XPathLiteral(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := '"';
  for I := 1 to Length(S) do
    if S[I] = '"' then
      Result := Result + '""'
    else
      Result := Result + Copy(S, I, 1);
  Result := Result + '"';
end;

{ The value of use-when="Text" on element E (XSLT 2.0 3.12): evaluated
  with the namespaces of E, no context item, no variables and the
  functions of XPath and XSLT (system-property(), function-available(),
  element-available() answer here; the others raise an error when
  called); an error in it is a static error. }
function TCompiler.UseWhen(M: TModule; E: Integer; const Text: TLandrixXmlUtf8): Boolean;
var
  Ctx: TLandrixXmlXPathStaticContext;
  Prefixes: TLandrixXmlUtf8Array;
  Uri: TLandrixXmlUtf8;
  I: Integer;
  Expr: TLandrixXmlXPathExpression;
  Def: TLandrixXmlXPathFunctionDef;
  Focus: TLandrixXmlXPathFocus;
begin
  Result := True;
  if FUseWhenEvaluator = nil then
  begin
    FUseWhenTree := TLandrixXmlXPathTree.Create;
    FUseWhenEvaluator := TLandrixXmlXPathEvaluator.Create(FUseWhenTree);
    FUseWhenDefs := TObjectList.Create;
    FUseWhenFunctions := TList.Create;
    for I := 0 to 5 do
    begin
      Def := TLandrixXmlXPathFunctionDef.Create;
      Def.Host := UseWhenHost;
      Def.Tag := I;
      FUseWhenDefs.Add(Def);
      FUseWhenFunctions.Add(Def);
    end;
    FUseWhenEvaluator.Functions := FUseWhenFunctions;
    FUseWhenTrue := TLandrixXmlXPathExpression.Create('true()', nil);
    FUseWhenFalse := TLandrixXmlXPathExpression.Create('false()', nil);
  end;
  Expr := nil;
  Ctx := TLandrixXmlXPathStaticContext.Create;
  try
    Ctx.Profile := xppSaxon;
    { XSLT predeclares neither xs nor fn (as NewContext) }
    Ctx.AddNamespace('xs', '');
    Ctx.AddNamespace('fn', '');
    Prefixes := M.Tree.InScopePrefixesUtf8(E);
    for I := 0 to Integer(Length(Prefixes)) - 1 do
      if (Prefixes[I] <> 'xml') and M.Tree.LookupNamespace(E, Prefixes[I], Uri) and (Uri <> '') then
      begin
        if Prefixes[I] <> '' then
          Ctx.AddNamespace(Prefixes[I], Uri);
        Ctx.AddNamespace('#ns:' + Prefixes[I], Uri);
      end;
    { in the order of the definitions (their tags) }
    Ctx.DeclareFunction(LandrixXmlXPathFunctionNamespace, 'system-property', 1);
    Ctx.DeclareFunction(LandrixXmlXPathFunctionNamespace, 'function-available', 1);
    Ctx.DeclareFunction(LandrixXmlXPathFunctionNamespace, 'function-available', 2);
    Ctx.DeclareFunction(LandrixXmlXPathFunctionNamespace, 'element-available', 1);
    Ctx.DeclareFunction(LandrixXmlXPathFunctionNamespace, 'static-base-uri', 0);
    Ctx.DeclareFunction(LandrixXmlXPathFunctionNamespace, 'resolve-uri', 1);
    Ctx.DefaultElementNamespace := XPathDefaultNamespace(M, E);
    FUseWhenModule := M;
    FUseWhenBase := StaticBase(M, E);
    try
      Expr := TLandrixXmlXPathExpression.Create(Text, Ctx);
      Focus.Node := -1;
      Focus.Item := LandrixXmlXPathEmpty;
      Focus.Position := 0;
      Focus.Size := 0;
      Result := FUseWhenEvaluator.EffectiveBoolean(FUseWhenEvaluator.EvaluateInFocus(Expr, Focus));
    except
      on X: ELandrixXmlXPathError do
        XPathFailed(M, E, X);
    end;
  finally
    Expr.Free;
    Ctx.Free;
  end;
end;

function TCompiler.UseWhenHost(Evaluator: TLandrixXmlXPathEvaluator; Def: TLandrixXmlXPathFunctionDef;
  const Args: array of TLandrixXmlXPathSequence; const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
var
  Uri, Local, Text: TLandrixXmlUtf8;
  Found: Boolean;
  Expr: TLandrixXmlXPathExpression;
  V, Arg0, Arg1: TLandrixXmlXPathSequence;
begin
  { the arguments one by one (FPC 3.2.2 hints at an open array otherwise) }
  Arg0 := LandrixXmlXPathEmpty;
  Arg1 := LandrixXmlXPathEmpty;
  if High(Args) >= 0 then
    Arg0 := Args[0];
  if High(Args) >= 1 then
    Arg1 := Args[1];
  case Def.Tag of
    4, 5:
      begin
        { static-base-uri(): the module's URI as xs:anyURI; resolve-uri()
          with one argument against it; a module without URI has no
          static base URI (as at run time) }
        if (Def.Tag = 4) and (FUseWhenBase = '') then
          Text := '()'
        else if Def.Tag = 4 then
          Text := 'xs:anyURI(' + XPathLiteral(FUseWhenBase) + ')'
        else
        begin
          V := Evaluator.ConvertSequence(Arg0, LandrixXmlXPathParseSequenceType('xs:string?', nil),
            'resolve-uri()');
          if V.Count = 0 then
          begin
            Result := LandrixXmlXPathEmpty;
            Exit;
          end;
          if FUseWhenBase = '' then
            Text := 'resolve-uri(' + XPathLiteral(Evaluator.ItemString(V.Items[0])) + ')'
          else
            Text := 'resolve-uri(' + XPathLiteral(Evaluator.ItemString(V.Items[0])) + ', ' +
              XPathLiteral(FUseWhenBase) + ')';
        end;
        Expr := TLandrixXmlXPathExpression.Create(Text, nil);
        try
          Result := Evaluator.EvaluateInFocus(Expr, Focus);
        finally
          Expr.Free;
        end;
        Exit;
      end;
    0:
      begin
        XsltNameArgument(Evaluator, Arg0, 'XTDE1390', 'system-property()', '', Uri, Local);
        Result := LandrixXmlXPathStringItem(XsltSystemProperty(Uri, Local));
        Exit;
      end;
    3:
      begin
        XsltNameArgument(Evaluator, Arg0, 'XTDE1440', 'element-available()', '#', Uri, Local);
        Found := (Uri = XsltNamespace) and XsltElementAvailable(Local);
      end;
  else
    XsltNameArgument(Evaluator, Arg0, 'XTDE1400', 'function-available()', LandrixXmlXPathFunctionNamespace,
      Uri, Local);
    if Def.Tag = 2 then
      Found := XsltFunctionAvailable(Evaluator, FC, Uri, Local, XsltArityArgument(Evaluator, Arg1))
    else
      Found := XsltFunctionAvailable(Evaluator, FC, Uri, Local, -1);
  end;
  if Found then
    Result := Evaluator.EvaluateInFocus(FUseWhenTrue, Focus)
  else
    Result := Evaluator.EvaluateInFocus(FUseWhenFalse, Focus);
end;

{ The module without the elements whose use-when is false (and their
  content; for the xsl:stylesheet element its content): a copy of the
  tree with the positions of the original nodes in Lines and Columns. }
procedure TCompiler.PruneUseWhen(M: TModule);
var
  Excluded: array of Boolean;
  Any: Boolean;
  T: TLandrixXmlXPathTree;
  Root: Integer;

  procedure Mark(I: Integer);
  var
    C, A: Integer;
    Xsl: Boolean;
  begin
    Xsl := M.Tree.NamespaceUriUtf8(I) = XsltNamespace;
    for A := I + 1 to I + M.Tree.AttributeCount[I] do
      if (M.Tree.LocalNameUtf8(A) = 'use-when') and ((Xsl and (M.Tree.NamespaceUriUtf8(A) = '')) or
        (not Xsl and (M.Tree.NamespaceUriUtf8(A) = XsltNamespace))) then
        if not UseWhen(M, I, M.Tree.ValueUtf8(A)) then
        begin
          Excluded[I] := True;
          Any := True;
          if I <> Root then
            Exit;
        end;
    if Excluded[I] then
      Exit;
    C := M.Tree.FirstChild(I);
    while C >= 0 do
    begin
      if M.Tree.Kind[C] = xnkElement then
        Mark(C);
      C := M.Tree.NextSibling[C];
    end;
  end;

  procedure Note(I: Integer);
  var
    N: Integer;
  begin
    N := T.Count - 1;
    if N >= Length(M.Lines) then
    begin
      SetLength(M.Lines, 2 * N + 64);
      SetLength(M.Columns, 2 * N + 64);
    end;
    M.Lines[N] := M.Tree.Line[I];
    M.Columns[N] := M.Tree.Column[I];
  end;

  procedure Copy1(I: Integer);
  var
    C, A, K, Before, D, Last: Integer;
    Prefixes, Uris: TLandrixXmlUtf8Array;
    S: TLandrixXmlUtf8;
    Drop: Boolean;
  begin
    Prefixes := nil;
    Uris := nil;
    case M.Tree.Kind[I] of
      xnkElement:
        begin
          T.BuildStartElement(M.Tree.NamespaceUriUtf8(I), M.Tree.PrefixUtf8(I), M.Tree.LocalNameUtf8(I));
          Note(I);
          M.Tree.GetDeclarations(I, Prefixes, Uris);
          for K := 0 to Integer(Length(Prefixes)) - 1 do
            T.BuildNamespace(Prefixes[K], Uris[K]);
          for A := I + 1 to I + M.Tree.AttributeCount[I] do
          begin
            T.BuildAttribute(M.Tree.NamespaceUriUtf8(A), M.Tree.PrefixUtf8(A), M.Tree.LocalNameUtf8(A),
              M.Tree.ValueUtf8(A));
            Note(A);
          end;
          if not Excluded[I] then
          begin
            C := M.Tree.FirstChild(I);
            while C >= 0 do
            begin
              if M.Tree.Kind[C] = xnkElement then
              begin
                if not Excluded[C] then
                  Copy1(C);
                C := M.Tree.NextSibling[C];
                Continue;
              end;
              { a run of text, comments and processing instructions up to
                the next element: white space is stripped before elements
                are left out (as Saxon does), so a run of white space goes
                here, not after its neighbours are merged }
              S := '';
              Last := C;
              D := C;
              while (D >= 0) and (M.Tree.Kind[D] <> xnkElement) do
              begin
                if M.Tree.Kind[D] = xnkText then
                  S := S + M.Tree.ValueUtf8(D);
                Last := D;
                D := M.Tree.NextSibling[D];
              end;
              Drop := (Trim8(S) = '') and not IsXsl(M, I, 'text') and not PreservesSpace(M.Tree, Last);
              while C >= 0 do
              begin
                if not (Drop and (M.Tree.Kind[C] = xnkText)) then
                  Copy1(C);
                if C = Last then
                  Break;
                C := M.Tree.NextSibling[C];
              end;
              C := D;
            end;
          end;
          T.BuildEndElement;
        end;
      xnkText:
        begin
          Before := T.Count;
          T.BuildText(M.Tree.ValueUtf8(I));
          if T.Count > Before then
            Note(I);
        end;
      xnkComment:
        begin
          T.BuildComment(M.Tree.ValueUtf8(I));
          Note(I);
        end;
      xnkProcessingInstruction:
        begin
          T.BuildProcessingInstruction(M.Tree.LocalNameUtf8(I), M.Tree.ValueUtf8(I));
          Note(I);
        end;
    else
      { attributes come with their element; the document node is not copied }
    end;
  end;

var
  C: Integer;
begin
  Excluded := nil;
  Root := M.Tree.DocumentElement;
  if Root < 0 then
    Exit;
  SetLength(Excluded, M.Tree.Count);
  Any := False;
  Mark(Root);
  if not Any then
    Exit;
  T := TLandrixXmlXPathTree.Create;
  try
    M.Lines := nil;
    M.Columns := nil;
    T.BeginBuild(True);
    SetLength(M.Lines, 64);
    SetLength(M.Columns, 64);
    M.Lines[0] := 0;
    M.Columns[0] := 0;
    C := M.Tree.FirstChild(0);
    while C >= 0 do
    begin
      Copy1(C);
      C := M.Tree.NextSibling[C];
    end;
    T.EndBuild;
    T.BaseUri := M.Tree.BaseUri;
  except
    T.Free;
    M.Lines := nil;
    M.Columns := nil;
    raise;
  end;
  SetLength(M.Lines, T.Count);
  SetLength(M.Columns, T.Count);
  if M.Owned then
    M.Tree.Free;
  M.Tree := T;
  M.Owned := True;
end;

{ whether E has content besides white space, comments and processing
  instructions (white space xml:space keeps counts) }
function HasContent(M: TModule; E: Integer): Boolean;
var
  C: Integer;
begin
  Result := True;
  C := M.Tree.FirstChild(E);
  while C >= 0 do
  begin
    if (M.Tree.Kind[C] = xnkElement) or (M.Tree.Kind[C] = xnkText) and
      ((Trim8(M.Tree.ValueUtf8(C)) <> '') or PreservesSpace(M.Tree, C)) then
      Exit;
    C := M.Tree.NextSibling[C];
  end;
  Result := False;
end;

{ the name of an element of the stylesheet for a message }
function DisplayName(M: TModule; E: Integer): string;
begin
  if M.Tree.NamespaceUriUtf8(E) = XsltNamespace then
    Result := 'xsl:' + LandrixXmlUtf8ToString(M.Tree.LocalNameUtf8(E))
  else
    Result := LandrixXmlUtf8ToString(M.Tree.LocalNameUtf8(E));
end;

{ CheckStandard for every element of a module (also those the compiler
  never looks at as instructions, such as xsl:when or xsl:param);
  XTSE0130 and XTSE0260 for its top-level elements }
procedure TCompiler.CheckModule(M: TModule);
var
  I, DataEnd: Integer;
begin
  PruneUseWhen(M);
  DataEnd := -1;
  I := 0;
  while I < M.Tree.Count do
  begin
    if M.Tree.Kind[I] = xnkElement then
    begin
      { a user-defined data element (a top-level element in another
        namespace): XSLT elements in it are no instructions (XSLT 2.0
        3.6.2); its own elements are checked (xsl:version, as Saxon) }
      if not M.Simplified and (M.Tree.Parent[I] = M.Tree.DocumentElement) and
        (M.Tree.NamespaceUriUtf8(I) <> XsltNamespace) and (M.Tree.NamespaceUriUtf8(I) <> '') then
      begin
        if M.Tree.NextSibling[I] >= 0 then
          DataEnd := M.Tree.NextSibling[I]
        else
          DataEnd := M.Tree.Count;
      end;
      if (I < DataEnd) and (M.Tree.NamespaceUriUtf8(I) = XsltNamespace) then
      begin
        Inc(I);
        Continue;
      end;
      if IgnoredDeclaration(M, I) then
      begin
        if M.Tree.NextSibling[I] >= 0 then
          I := M.Tree.NextSibling[I]
        else
          I := M.Tree.Count;
        Continue;
      end;
      CheckStandard(M, I, I < DataEnd);
    end;
    Inc(I);
  end;
  if M.Simplified then
    Exit;
  I := M.Tree.FirstChild(M.Tree.DocumentElement);
  while I >= 0 do
  begin
    if M.Tree.Kind[I] = xnkElement then
    begin
      { a top-level element in no namespace: XTSE0130 }
      if M.Tree.NamespaceUriUtf8(I) = '' then
        Fail(M, I, 'XTSE0130', 'the top-level element ' + LandrixXmlUtf8ToString(M.Tree.LocalNameUtf8(I)) +
          ' is in no namespace');
      { declarations that must be empty (xsl:mode is checked where it is
        compiled; xsl:namespace-alias with content is accepted, as Saxon) }
      if (IsXsl(M, I, 'include') or IsXsl(M, I, 'import') or IsXsl(M, I, 'strip-space') or
        IsXsl(M, I, 'preserve-space') or IsXsl(M, I, 'output') or IsXsl(M, I, 'decimal-format')) and
        HasContent(M, I) then
        Fail(M, I, 'XTSE0260', DisplayName(M, I) + ' must be empty');
    end;
    I := M.Tree.NextSibling[I];
  end;
end;

{ the Clark name of a mode name: a QName (no default namespace) or an
  EQName (Q, the URI in braces with its white space collapsed, the local
  name); XTSE0020 if it is neither (#unnamed, #default too), XTSE0280 for
  an undeclared prefix, XTSE0080 for a reserved namespace }
function TCompiler.ModeName(M: TModule; E: Integer; const Value: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  V, Uri: TLandrixXmlUtf8;
  K: Integer;
begin
  V := Trim8(Value);
  if Copy(V, 1, 2) = 'Q{' then
  begin
    K := Pos8('}', V);
    if (K = 0) or not IsNCName8(Copy(V, K + 1, MaxInt)) or (Pos8('{', Copy(V, 3, K - 3)) > 0) then
      Fail(M, E, 'XTSE0020', 'not a mode name: "' + LandrixXmlUtf8ToString(Value) + '"');
    Uri := Collapse8(Copy(V, 3, K - 3));
    Result := XsltClarkOf(Uri, Copy(V, K + 1, MaxInt));
  end
  else
  begin
    Result := QNameToClark(M, E, V, False);
    Uri := '';
    if Copy(Result, 1, 1) = '{' then
      Uri := Copy(Result, 2, Pos8('}', Result) - 2);
  end;
  if ReservedNamespace(Uri) then
    Fail(M, E, 'XTSE0080', 'a mode in a reserved namespace: "' + LandrixXmlUtf8ToString(Value) + '"');
end;

{ the default mode at E: the [xsl:]default-mode of E or of the nearest
  ancestor that has one (default-mode on an XSLT element, xsl:default-mode
  on another), '' (the unnamed mode) for #unnamed or none }
function TCompiler.DefaultModeOf(M: TModule; E: Integer): TLandrixXmlUtf8;
var
  A, I: Integer;
  Xsl: Boolean;
  V: TLandrixXmlUtf8;
begin
  Result := '';
  A := E;
  while A >= 0 do
  begin
    if M.Tree.Kind[A] = xnkElement then
    begin
      Xsl := M.Tree.NamespaceUriUtf8(A) = XsltNamespace;
      for I := A + 1 to A + M.Tree.AttributeCount[A] do
        if (M.Tree.LocalNameUtf8(I) = 'default-mode') and
          (Xsl and (M.Tree.NamespaceUriUtf8(I) = '') or not Xsl and (M.Tree.NamespaceUriUtf8(I) = XsltNamespace)) then
        begin
          V := Trim8(M.Tree.ValueUtf8(I));
          if V <> '#unnamed' then
            Result := ModeName(M, A, V);
          Exit;
        end;
    end;
    A := M.Tree.Parent[A];
  end;
end;

{ an attribute of an xsl:mode declaration, normalized: white space
  trimmed, a boolean as yes or no (XTSE0020 for another value), the names
  of use-accumulators sorted }
function TCompiler.ModeDeclValue(D: TDecl; const Local: TLandrixXmlUtf8; out Value: TLandrixXmlUtf8): Boolean;
var
  V, B: TLandrixXmlUtf8;
  K: Integer;

  procedure Check(const Allowed: string);
  begin
    if (V = '') or (Pos8(' ', V) > 0) or (Pos(' ' + LandrixXmlUtf8ToString(V) + ' ', ' ' + Allowed + ' ') = 0) then
      Fail(D.Module, D.Element, 'XTSE0020', 'xsl:mode ' + LandrixXmlUtf8ToString(Local) + ' is one of ' + Allowed +
        ', not "' + LandrixXmlUtf8ToString(V) + '"');
  end;

begin
  Result := Attr(D.Module, D.Element, Local, V);
  if not Result then
    Exit;
  V := Trim8(V);
  if (Local = 'streamable') or (Local = 'warning-on-no-match') or (Local = 'warning-on-multiple-match') or
    (Local = 'typed') and (V <> 'strict') and (V <> 'lax') and (V <> 'unspecified') then
  begin
    if YesNoAttr(D.Module, D.Element, Local) then
      V := 'yes'
    else
      V := 'no';
  end
  else if Local = 'on-no-match' then
    Check('deep-copy shallow-copy deep-skip shallow-skip text-only-copy fail')
  else if Local = 'on-multiple-match' then
    Check('use-last fail')
  else if Local = 'visibility' then
    Check('public private final')
  else if Local = 'use-accumulators' then
  begin
    { no accumulator is declared (xsl:accumulator is not supported): the
      first name is XTSE3300, XTSE0280 if its prefix is undeclared (as in
      Saxon); #all and none are the same then }
    V := Collapse8(V);
    if (V <> '') and (V <> '#all') then
    begin
      B := V;
      K := Pos8(' ', B);
      if K > 0 then
        B := Copy(B, 1, K - 1);
      K := Pos8(':', B);
      if (Copy(B, 1, 2) <> 'Q{') and (K > 0) and IsNCName8(Copy(B, 1, K - 1)) and
        IsNCName8(Copy(B, K + 1, MaxInt)) then
        QNameToClark(D.Module, D.Element, B, False);
      Fail(D.Module, D.Element, 'XTSE3300', 'no accumulator is declared: "' + LandrixXmlUtf8ToString(V) + '"');
    end;
  end;
  Value := V;
end;

{ The xsl:mode declarations (XSLT 3.0): each attribute of a mode from the
  declaration of the highest import precedence that has it (XTSE0545 for
  two of that precedence with different values, except streamable and
  use-accumulators, which change nothing here: Saxon HE does not stream
  and no accumulator is declared). An xsl:mode is empty (XTSE0260, white
  space xml:space keeps counts); the unnamed mode is private (XTSE0020).
  An initial mode must not say visibility="private" (Saxon; the default
  visibility does not restrict it); typed="strict" is typed="yes" without
  a schema, as in Saxon HE. }
procedure TCompiler.CompileModes;
const
  AttrCount = 8;
  AttrNames: array[0..AttrCount - 1] of string = ('streamable', 'use-accumulators', 'on-no-match',
    'on-multiple-match', 'warning-on-no-match', 'warning-on-multiple-match', 'typed', 'visibility');
var
  I, J, K, C: Integer;
  D, E2: TDecl;
  Name, V: TLandrixXmlUtf8;
  Names: TXsltStringList;
  Done: array of Boolean;
  Mode: TXsltMode;
  Values: array[0..AttrCount - 1] of TLandrixXmlUtf8;
  Precs: array[0..AttrCount - 1] of Integer;
  Conflicts: array[0..AttrCount - 1] of TDecl;
begin
  Done := nil;
  Names := TXsltStringList.Create;
  try
    SetLength(Done, FModeDecls.Count);
    { the name of each declaration, checked in declaration order }
    for I := 0 to Integer(FModeDecls.Count) - 1 do
    begin
      D := TDecl(FModeDecls[I]);
      C := D.Module.Tree.FirstChild(D.Element);
      while C >= 0 do
      begin
        if (D.Module.Tree.Kind[C] = xnkElement) or (D.Module.Tree.Kind[C] = xnkText) and
          ((Trim8(D.Module.Tree.ValueUtf8(C)) <> '') or PreservesSpace(D.Module.Tree, C)) then
          Fail(D.Module, D.Element, 'XTSE0260', 'xsl:mode is empty');
        C := D.Module.Tree.NextSibling[C];
      end;
      Name := '';
      if Attr(D.Module, D.Element, 'name', V) then
        Name := ModeName(D.Module, D.Element, V);
      Names.Add(LandrixXmlUtf8ToKey(Name));
      if (Name = '') and Attr(D.Module, D.Element, 'visibility', V) and (Trim8(V) <> 'private') then
        Fail(D.Module, D.Element, 'XTSE0020', 'the unnamed mode is private');
      for K := 0 to AttrCount - 1 do
        ModeDeclValue(D, LandrixXmlStringToUtf8(AttrNames[K]), V);
    end;
    for I := 0 to Integer(FModeDecls.Count) - 1 do
    begin
      if Done[I] then
        Continue;
      for K := 0 to AttrCount - 1 do
      begin
        Values[K] := '';
        Precs[K] := -1;
        Conflicts[K] := nil;
      end;
      for J := I to Integer(FModeDecls.Count) - 1 do
        if Names[J] = Names[I] then
        begin
          Done[J] := True;
          E2 := TDecl(FModeDecls[J]);
          for K := 0 to AttrCount - 1 do
            if ModeDeclValue(E2, LandrixXmlStringToUtf8(AttrNames[K]), V) then
            begin
              if E2.Precedence > Precs[K] then
              begin
                Precs[K] := E2.Precedence;
                Values[K] := V;
                Conflicts[K] := nil;
              end
              else if (E2.Precedence = Precs[K]) and (V <> Values[K]) and (Conflicts[K] = nil) then
                Conflicts[K] := E2;
            end;
        end;
      Name := LandrixXmlKeyToUtf8(Names[I]);
      for K := 2 to AttrCount - 1 do
        if Conflicts[K] <> nil then
          Fail(Conflicts[K].Module, Conflicts[K].Element, 'XTSE0545', 'two xsl:mode declarations of one import ' +
            'precedence give the mode "' + LandrixXmlUtf8ToString(Name) + '" different values of ' + AttrNames[K]);
      Mode := ModeOf(Name);
      Mode.IsPrivate := Values[7] = 'private';
      Mode.NoMatchGiven := Values[2] <> '';
      Mode.FailOnMultiple := Values[3] = 'fail';
      Mode.Typed := (Values[6] = 'yes') or (Values[6] = 'lax') or (Values[6] = 'strict');
      if Values[2] = 'deep-copy' then
        Mode.OnNoMatch := xnmDeepCopy
      else if Values[2] = 'shallow-copy' then
        Mode.OnNoMatch := xnmShallowCopy
      else if Values[2] = 'deep-skip' then
        Mode.OnNoMatch := xnmDeepSkip
      else if Values[2] = 'shallow-skip' then
        Mode.OnNoMatch := xnmShallowSkip
      else if Values[2] = 'fail' then
        Mode.OnNoMatch := xnmFail
      else
        Mode.OnNoMatch := xnmTextOnlyCopy;
    end;
  finally
    Names.Free;
  end;
end;

{ --- expressions --------------------------------------------------------------- }

{ The name a static context declares for a variable: the local name, with
  a prefix the context binds to the namespace. The prefix starts with "#",
  so that it is never one a stylesheet can bind or write. }
function TCompiler.VarName(const Clark: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
  Uri, Local: TLandrixXmlUtf8;
begin
  Result := Clark;
  if (Clark = '') or (Clark[1] <> '{') then
    Exit;
  I := Pos8('}', Clark);
  Uri := Copy(Clark, 2, I - 2);
  Local := Copy(Clark, I + 1, Length(Clark) - I);
  I := FVarUris.IndexOf(LandrixXmlUtf8ToKey(Uri));
  if I < 0 then
    I := FVarUris.Add(LandrixXmlUtf8ToKey(Uri));
  Result := '#v' + LandrixXmlStringToUtf8(IntToStr(I)) + ':' + Local;
end;

function TCompiler.NewContext(M: TModule; E: Integer; Scope: TScope): TLandrixXmlXPathStaticContext;
var
  Prefixes, Names: TLandrixXmlUtf8Array;
  Uri: TLandrixXmlUtf8;
  I, J, N, K, Base: Integer;
  G: TXsltGlobal;
begin
  Names := nil;
  Base := BaseIndex(M, E);
  Result := TLandrixXmlXPathStaticContext.Create;
  try
    Result.Profile := xppSaxon;
    Result.XPath10Compatible := Backwards(M, E);
    Result.DefaultElementNamespace := XPathDefaultNamespace(M, E);
    { the stylesheet's expressions see only the namespaces declared in
      it: XSLT predeclares neither xs nor fn (XSLT 2.0 5.4.1; Saxon
      XPST0081, namespace-6202) }
    Result.AddNamespace('xs', '');
    Result.AddNamespace('fn', '');
    Prefixes := M.Tree.InScopePrefixesUtf8(E);
    for I := 0 to Integer(Length(Prefixes)) - 1 do
      if (Prefixes[I] <> 'xml') and M.Tree.LookupNamespace(E, Prefixes[I], Uri) and (Uri <> '') then
      begin
        if Prefixes[I] <> '' then
          Result.AddNamespace(Prefixes[I], Uri);
        { the stylesheet's own bindings once more, under a key no XPath
          name has ('#ns:' and the prefix, '#ns:' the default namespace;
          the variables' URIs use '#v' and a number): the
          names function-available() and the others get as strings are
          resolved with these alone (not with the xs and fn the XPath
          context adds) }
        Result.AddNamespace('#ns:' + Prefixes[I], Uri);
      end;
    if FInternalCall then
      Result.AddNamespace('xsl-internal-f', XsltInternalNamespace);
    { the variables in slot order, named by their expanded names }
    N := FC.GlobalCount;
    if (Scope <> nil) and (Scope.NextSlot > N) then
      N := Scope.NextSlot;
    SetLength(Names, N);
    for I := 0 to N - 1 do
      Names[I] := '#' + LandrixXmlStringToUtf8(IntToStr(I));
    for I := 0 to Integer(FC.Globals.Count) - 1 do
    begin
      G := TXsltGlobal(FC.Globals[I]);
      Names[G.Slot] := VarName(G.Name);
    end;
    if Scope <> nil then
      for I := 0 to Scope.Count - 1 do
      begin
        { a later binding of the same name hides the earlier ones }
        for J := 0 to Integer(FC.Globals.Count) - 1 do
          if TXsltGlobal(FC.Globals[J]).Name = Scope.Clarks[I] then
            Names[TXsltGlobal(FC.Globals[J]).Slot] := '#' + LandrixXmlStringToUtf8(IntToStr(TXsltGlobal(FC.Globals[J]).Slot));
        for J := 0 to I - 1 do
          if Scope.Clarks[J] = Scope.Clarks[I] then
            Names[Scope.Slots[J]] := '#' + LandrixXmlStringToUtf8(IntToStr(Scope.Slots[J]));
        Names[Scope.Slots[I]] := VarName(Scope.Clarks[I]);
      end;
    for I := 0 to Integer(FVarUris.Count) - 1 do
      Result.AddNamespace('#v' + LandrixXmlStringToUtf8(IntToStr(I)),
        LandrixXmlKeyToUtf8(FVarUris[I]));
    for I := 0 to N - 1 do
      Result.DeclareVariable(Names[I]);
    { the functions; those of a module (doc(), document()) under their
      own names for the expressions of that module only }
    for I := 0 to Integer(Length(FC.FunctionNames)) - 1 do
    begin
      if (I = XfnGlobal) and not FInternalCall then
        { out of reach of the stylesheet's expressions }
        K := Result.DeclareFunction(XsltInternalNamespace, '#global', FC.FunctionArities[I])
      else if (FC.FunctionModules[I] >= 0) and (FC.FunctionModules[I] <> Base) then
        K := Result.DeclareFunction(XsltInternalNamespace, '#m' + LandrixXmlStringToUtf8(IntToStr(I)),
          FC.FunctionArities[I])
      else
        K := Result.DeclareFunction(FC.FunctionUris[I], FC.FunctionNames[I], FC.FunctionArities[I]);
      Result.SetFunctionFlags(K, FC.FunctionFlags[I]);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TCompiler.Compile(M: TModule; E: Integer; const Text: TLandrixXmlUtf8;
  Scope: TScope): TLandrixXmlXPathExpression;
var
  Ctx: TLandrixXmlXPathStaticContext;
begin
  Result := nil;
  Ctx := NewContext(M, E, Scope);
  try
    try
      Result := TLandrixXmlXPathExpression.Create(Text, Ctx);
    except
      on X: ELandrixXmlXPathError do
        XPathFailed(M, E, X);
    end;
  finally
    Ctx.Free;
  end;
  FC.Expressions.Add(Result);
end;

function TCompiler.CompileAttr(M: TModule; E: Integer; const Local: TLandrixXmlUtf8;
  Scope: TScope): TLandrixXmlXPathExpression;
var
  V: TLandrixXmlUtf8;
begin
  Result := nil;
  if Attr(M, E, Local, V) then
    Result := Compile(M, E, V, Scope);
end;

{ whether an expression is only white space and XPath comments (empty) }
function OnlyComments(const S: TLandrixXmlUtf8): Boolean;
var
  I, Depth: Integer;
begin
  Result := False;
  I := 1;
  Depth := 0;
  while I <= Length(S) do
  begin
    if (S[I] = '(') and (I < Length(S)) and (S[I + 1] = ':') then
    begin
      Inc(Depth);
      Inc(I, 2);
    end
    else if (Depth > 0) and (S[I] = ':') and (I < Length(S)) and (S[I + 1] = ')') then
    begin
      Dec(Depth);
      Inc(I, 2);
    end
    else if (Depth > 0) or (S[I] in [#9, #10, #13, ' ']) then
      Inc(I)
    else
      Exit;
  end;
  Result := Depth = 0;
end;

function TCompiler.CompileAvt(M: TModule; E: Integer; const Text: TLandrixXmlUtf8; Scope: TScope): TXsltAvt;
var
  I, Start, Depth, N, Comment: Integer;
  Lit: TLandrixXmlUtf8;
  Quote: AnsiChar;

  procedure AddPart(const S: TLandrixXmlUtf8; X: TLandrixXmlXPathExpression);
  begin
    N := Integer(Length(Result.Parts));
    SetLength(Result.Parts, N + 1);
    SetLength(Result.Exprs, N + 1);
    Result.Parts[N] := S;
    Result.Exprs[N] := X;
  end;

begin
  Result := TXsltAvt.Create;
  FC.Expressions.Add(Result);
  Lit := '';
  I := 1;
  while I <= Length(Text) do
  begin
    if Text[I] = '{' then
    begin
      if (I < Length(Text)) and (Text[I + 1] = '{') then
      begin
        Lit := Lit + '{';
        Inc(I, 2);
        Continue;
      end;
      if Lit <> '' then
        AddPart(Lit, nil);
      Lit := '';
      Start := I + 1;
      Depth := 0;
      Quote := #0;
      Inc(I);
      while (I <= Length(Text)) and ((Text[I] <> '}') or (Quote <> #0) or (Depth > 0)) do
      begin
        if Quote <> #0 then
        begin
          if Text[I] = Quote then
            Quote := #0;
        end
        else if Text[I] in ['''', '"'] then
          Quote := Text[I]
        else if (Text[I] = '(') and (I < Length(Text)) and (Text[I + 1] = ':') then
        begin
          { an XPath comment (nested ones too): its braces do not count }
          Comment := 1;
          Inc(I, 2);
          while (I <= Length(Text)) and (Comment > 0) do
            if (Text[I] = '(') and (I < Length(Text)) and (Text[I + 1] = ':') then
            begin
              Inc(Comment);
              Inc(I, 2);
            end
            else if (Text[I] = ':') and (I < Length(Text)) and (Text[I + 1] = ')') then
            begin
              Dec(Comment);
              Inc(I, 2);
            end
            else
              Inc(I);
          Continue;
        end
        else if Text[I] = '{' then
          Inc(Depth)
        else if Text[I] = '}' then
          Dec(Depth);
        Inc(I);
      end;
      if I > Length(Text) then
        Fail(M, E, 'XTSE0350', 'an attribute value template without "}"');
      { in a text value template empty braces are the empty sequence (Saxon) }
      if not FTextTemplate or not OnlyComments(Copy(Text, Start, I - Start)) then
        AddPart('', Compile(M, E, Copy(Text, Start, I - Start), Scope));
      Inc(I);
    end
    else if Text[I] = '}' then
    begin
      if (I < Length(Text)) and (Text[I + 1] = '}') then
      begin
        Lit := Lit + '}';
        Inc(I, 2);
        Continue;
      end;
      Fail(M, E, 'XTSE0370', 'a single "}" in an attribute value template');
    end
    else
    begin
      Lit := Lit + Copy(Text, I, 1);
      Inc(I);
    end;
  end;
  if (Lit <> '') or (Length(Result.Parts) = 0) then
    AddPart(Lit, nil);
end;

{ expand-text in force for the content of element E: the nearest
  [xsl:]expand-text of E and its ancestors in the module (default no) }
function TCompiler.ExpandText(M: TModule; E: Integer): Boolean;
var
  A: Integer;
  V: TLandrixXmlUtf8;
  Xsl: Boolean;
begin
  Result := False;
  while E >= 0 do
  begin
    if M.Tree.Kind[E] = xnkElement then
    begin
      Xsl := M.Tree.NamespaceUriUtf8(E) = XsltNamespace;
      for A := E + 1 to E + M.Tree.AttributeCount[E] do
        if (M.Tree.LocalNameUtf8(A) = 'expand-text') and (Xsl and (M.Tree.NamespaceUriUtf8(A) = '') or
          not Xsl and (M.Tree.NamespaceUriUtf8(A) = XsltNamespace)) then
        begin
          V := Trim8(M.Tree.ValueUtf8(A));
          Result := (V = 'yes') or (V = 'true') or (V = '1');
          Exit;
        end;
    end;
    E := M.Tree.Parent[E];
  end;
end;

{ the text of Instr (xskText) as a text value template: literal text
  stays in Text }
procedure TCompiler.CompileText(M: TModule; E: Integer; Instr: TXsltInstr; Scope: TScope);
var
  A: TXsltAvt;
  I: Integer;
  V: TLandrixXmlUtf8;
begin
  FTextTemplate := True;
  try
    A := CompileAvt(M, E, Instr.Text, Scope);
  finally
    FTextTemplate := False;
  end;
  if A.IsLiteral then
  begin
    V := '';
    for I := 0 to Integer(Length(A.Parts)) - 1 do
      V := V + A.Parts[I];
    Instr.Text := V;
  end
  else
    Instr.TextAvt := A;
end;

function TCompiler.ParseType(M: TModule; E: Integer; Scope: TScope; out T: TLandrixXmlXPathSequenceType): Boolean;
var
  V: TLandrixXmlUtf8;
  Ctx: TLandrixXmlXPathStaticContext;
begin
  Result := Attr(M, E, 'as', V);
  if not Result then
    Exit;
  Ctx := NewContext(M, E, Scope);
  try
    try
      T := LandrixXmlXPathParseSequenceType(V, Ctx);
    except
      on X: ELandrixXmlXPathError do
        raise ELandrixXmlXsltError.CreateXslt(xecXPath, X.XPathCode,
          Copy(X.Message, Length(X.XPathCode) + 3, MaxInt), M.Uri, M.LineOf(E), M.ColumnOf(E));
    end;
  finally
    Ctx.Free;
  end;
end;

{ --- instructions ----------------------------------------------------------------- }

function TCompiler.NewInstr(Kind: TXsltInstrKind; M: TModule; E: Integer): TXsltInstr;
begin
  Result := TXsltInstr.Create(Kind);
  Result.Module := M.Uri;
  Result.BaseUri := StaticBase(M, E);
  Result.Line := M.LineOf(E);
  Result.Column := M.ColumnOf(E);
  Result.Backwards := Backwards(M, E);
end;

{ xml:space="preserve" on the node or an ancestor (nearest wins) }
function PreservesSpace(T: TLandrixXmlXPathTree; N: Integer): Boolean;
var
  I, D: Integer;
begin
  Result := False;
  { white space before xsl:param or xsl:sort goes whatever xml:space says
    (comments and processing instructions are removed first) }
  D := T.NextSibling[N];
  while (D >= 0) and (T.Kind[D] in [xnkComment, xnkProcessingInstruction]) do
    D := T.NextSibling[D];
  if (D >= 0) and (T.Kind[D] = xnkElement) and (T.NamespaceUriUtf8(D) = XsltNamespace) and
    ((T.LocalNameUtf8(D) = 'param') or (T.LocalNameUtf8(D) = 'sort')) then
    Exit;
  while N >= 0 do
  begin
    if T.Kind[N] = xnkElement then
      for I := N + 1 to N + T.AttributeCount[N] do
        if (T.NamespaceUriUtf8(I) = LandrixXmlNamespaceXml) and (T.LocalNameUtf8(I) = 'space') then
        begin
          Result := T.ValueUtf8(I) = 'preserve';
          Exit;
        end;
    N := T.Parent[N];
  end;
end;

{ The sequence constructor of Parent's children from First on (-1: all);
  the variables declared in it are visible to the instructions after
  them and leave the scope at its end. }
procedure TCompiler.CompileBody(M: TModule; Parent: Integer; Scope: TScope; Body: TObjectList; First: Integer);
var
  C, SavedCount, D, Last: Integer;
  I: TXsltInstr;
  S: TLandrixXmlUtf8;
begin
  SavedCount := Scope.Count;
  if First < 0 then
    C := M.Tree.FirstChild(Parent)
  else
    C := First;
  while C >= 0 do
  begin
    case M.Tree.Kind[C] of
      xnkText:
        begin
          { the text up to the next element: comments and processing
            instructions of the stylesheet are removed before white space
            is stripped, so the text around them is one text node }
          S := M.Tree.ValueUtf8(C);
          Last := C;
          D := M.Tree.NextSibling[C];
          while (D >= 0) and (M.Tree.Kind[D] in [xnkText, xnkComment, xnkProcessingInstruction]) do
          begin
            if M.Tree.Kind[D] = xnkText then
              S := S + M.Tree.ValueUtf8(D);
            Last := D;
            D := M.Tree.NextSibling[D];
          end;
          if (Trim8(S) <> '') or PreservesSpace(M.Tree, Last) then
          begin
            I := NewInstr(xskText, M, C);
            I.Text := S;
            Body.Add(I);
            if ExpandText(M, Parent) then
              CompileText(M, Parent, I, Scope);
          end;
          C := Last;
        end;
      xnkElement:
        begin
          if IsXsl(M, C, '') then
            I := CompileInstr(M, C, Scope)
          else if IsExtension(M, C) then
            I := CompileExtension(M, C, Scope, True)
          else
            I := CompileLiteral(M, C, Scope);
          if I <> nil then
            Body.Add(I);
        end;
    else
      { comments and processing instructions of the stylesheet }
    end;
    C := M.Tree.NextSibling[C];
  end;
  Scope.Count := SavedCount;
end;

{ The namespaces a literal result element copies: those in scope at E but
  the XSLT namespace, xml and the excluded prefixes of E and its ancestors
  (exclude-result-prefixes on XSLT elements, xsl:exclude-result-prefixes
  on literal result elements), and the extension namespaces
  (extension-element-prefixes, the same way). }
procedure LiteralNamespaces(M: TModule; E: Integer; Instr: TXsltInstr);
var
  Prefixes, Excluded: TLandrixXmlUtf8Array;
  Uri, V, P: TLandrixXmlUtf8;
  I, J, N, Count: Integer;
  Skip: Boolean;

  procedure AddUri(Element: Integer; const Prefix: TLandrixXmlUtf8);
  var
    U: TLandrixXmlUtf8;
  begin
    if M.Tree.LookupNamespace(Element, Prefix, U) then
    begin
      SetLength(Excluded, Length(Excluded) + 1);
      Excluded[High(Excluded)] := U;
    end;
  end;

  { the namespace URIs exclude-result-prefixes names, resolved where it
    is (a prefix bound to another URI further in is not excluded) }
  procedure AddExcluded(Element: Integer; Stylesheet: Boolean; const Name: TLandrixXmlUtf8);
  var
    K, L, Start: Integer;
    W: TLandrixXmlUtf8;
    InScope: TLandrixXmlUtf8Array;
  begin
    InScope := nil;
    V := '';
    for K := Element + 1 to Element + M.Tree.AttributeCount[Element] do
      if (M.Tree.LocalNameUtf8(K) = Name) and
        ((Stylesheet and (M.Tree.NamespaceUriUtf8(K) = '')) or
        (not Stylesheet and (M.Tree.NamespaceUriUtf8(K) = XsltNamespace))) then
        V := M.Tree.ValueUtf8(K);
    V := V + ' ';
    Start := 1;
    for K := 1 to Length(V) do
      if V[K] in [#9, #10, #13, ' '] then
      begin
        W := Copy(V, Start, K - Start);
        Start := K + 1;
        if W = '' then
          Continue;
        { extension-element-prefixes: #default is no namespace (Saxon) }
        if (Name = 'extension-element-prefixes') and ((W = '#default') or (W = '#all')) then
          Continue;
        if W = '#all' then
        begin
          InScope := M.Tree.InScopePrefixesUtf8(Element);
          for L := 0 to Integer(Length(InScope)) - 1 do
            AddUri(Element, InScope[L]);
        end
        else
        begin
          if W = '#default' then
            W := '';
          AddUri(Element, W);
        end;
      end;
  end;

begin
  Excluded := nil;
  N := E;
  while N >= 0 do
  begin
    if M.Tree.Kind[N] = xnkElement then
    begin
      AddExcluded(N, M.Tree.NamespaceUriUtf8(N) = XsltNamespace, 'exclude-result-prefixes');
      AddExcluded(N, M.Tree.NamespaceUriUtf8(N) = XsltNamespace, 'extension-element-prefixes');
    end;
    N := M.Tree.Parent[N];
  end;
  Prefixes := M.Tree.InScopePrefixesUtf8(E);
  Count := 0;
  SetLength(Instr.NsPrefixes, Length(Prefixes));
  SetLength(Instr.NsUris, Length(Prefixes));
  for I := 0 to Integer(Length(Prefixes)) - 1 do
  begin
    P := Prefixes[I];
    if (P = 'xml') or not M.Tree.LookupNamespace(E, P, Uri) then
      Continue;
    { the XSLT namespace is never copied (unless it is the result of an
      alias: ApplyAlias) }
    Skip := Uri = XsltNamespace;
    { an excluded namespace the element or an attribute uses is no
      namespace node: the namespace fixup declares it (and gives the
      element another prefix if xsl:namespace binds this one otherwise,
      as Saxon does) }
    for J := 0 to Integer(Length(Excluded)) - 1 do
      if Excluded[J] = Uri then
        Skip := True;
    if Skip then
    begin
      N := Integer(Length(Instr.ExPrefixes));
      SetLength(Instr.ExPrefixes, N + 1);
      SetLength(Instr.ExUris, N + 1);
      Instr.ExPrefixes[N] := P;
      Instr.ExUris[N] := Uri;
      Continue;
    end;
    Instr.NsPrefixes[Count] := P;
    Instr.NsUris[Count] := Uri;
    Inc(Count);
  end;
  SetLength(Instr.NsPrefixes, Count);
  SetLength(Instr.NsUris, Count);
end;

function HasFallback(M: TModule; E: Integer): Boolean;
var
  C: Integer;
begin
  Result := False;
  C := M.Tree.FirstChild(E);
  while C >= 0 do
  begin
    if (M.Tree.Kind[C] = xnkElement) and (M.Tree.NamespaceUriUtf8(C) = XsltNamespace) and
      (M.Tree.LocalNameUtf8(C) = 'fallback') then
      Result := True;
    C := M.Tree.NextSibling[C];
  end;
end;

{ an extension instruction: no extension is known, so its xsl:fallback
  children are what it does (the other children are ignored) }
function TCompiler.CompileExtension(M: TModule; E: Integer; Scope: TScope; CheckOthers: Boolean): TXsltInstr;
var
  C: Integer;
begin
  Result := NewInstr(xskExtension, M, E);
  try
    Result.Text := M.Tree.NameUtf8(E);
    { the other children are compiled only for their static errors (as
      Saxon checks them); kept in NonMatching (never run), as compiled
      instructions may be registered for later checks }
    if CheckOthers then
    begin
      Result.NonMatching := TObjectList.Create;
      CompileBody(M, E, Scope, Result.NonMatching, -1);
    end;
    C := M.Tree.FirstChild(E);
    while C >= 0 do
    begin
      if (M.Tree.Kind[C] = xnkElement) and IsXsl(M, C, 'fallback') then
      begin
        Result.HasFallback := True;
        CompileBody(M, C, Scope, Result.Body, -1);
      end;
      C := M.Tree.NextSibling[C];
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TCompiler.CompileLiteral(M: TModule; E: Integer; Scope: TScope): TXsltInstr;
var
  A: Integer;
  T: TXsltAttributeTemplate;
  Uri: TLandrixXmlUtf8;
begin
  Result := NewInstr(xskLiteralElement, M, E);
  try
    Result.NamespaceUri := M.Tree.NamespaceUriUtf8(E);
    Result.Prefix := M.Tree.PrefixUtf8(E);
    Result.LocalName := M.Tree.LocalNameUtf8(E);
    LiteralNamespaces(M, E, Result);
    for A := E + 1 to E + M.Tree.AttributeCount[E] do
    begin
      Uri := M.Tree.NamespaceUriUtf8(A);
      if Uri = XsltNamespace then
      begin
        if M.Tree.LocalNameUtf8(A) = 'use-attribute-sets' then
          Result.UseSets := UseAttributeSets(M, E, M.Tree.ValueUtf8(A));
        Continue;
      end;
      T := TXsltAttributeTemplate.Create;
      Result.Attributes.Add(T);
      T.NamespaceUri := Uri;
      T.Prefix := M.Tree.PrefixUtf8(A);
      T.LocalName := M.Tree.LocalNameUtf8(A);
      T.Value := CompileAvt(M, E, M.Tree.ValueUtf8(A), Scope);
    end;
    CompileBody(M, E, Scope, Result.Body, -1);
  except
    Result.Free;
    raise;
  end;
end;

procedure ScopeNamespaces(M: TModule; E: Integer; Instr: TXsltInstr); forward;

{ the text of an attribute value template without expressions (its
  literal parts) }
function LiteralOf(A: TXsltAvt): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Integer(Length(A.Parts)) - 1 do
    Result := Result + A.Parts[I];
end;

{ xsl:result-document: the serialization attributes are attribute value
  templates; literal values are checked here as on xsl:output }
function TCompiler.CompileResultDocument(M: TModule; E: Integer; Scope: TScope): TXsltInstr;
var
  I, N: Integer;
  L, V, Name, Bad: TLandrixXmlUtf8;
  A: TXsltAvt;
begin
  Result := NewInstr(xskResultDocument, M, E);
  try
    ScopeNamespaces(M, E, Result);
    for I := E + 1 to E + M.Tree.AttributeCount[E] do
    begin
      if M.Tree.NamespaceUriUtf8(I) <> '' then
        Continue;
      L := M.Tree.LocalNameUtf8(I);
      V := M.Tree.ValueUtf8(I);
      { standard attributes (CheckStandard) }
      if (L = 'version') or (L = 'exclude-result-prefixes') or (L = 'extension-element-prefixes') or
        (L = 'xpath-default-namespace') or (L = 'default-collation') or (L = 'use-when') or
        (L = 'expand-text') or (L = 'default-mode') or (L = 'default-validation') or
        (L = 'input-type-annotations') then
        Continue;
      if L = 'href' then
      begin
        Result.HrefAvt := CompileAvt(M, E, V, Scope);
        Continue;
      end;
      if L = 'format' then
      begin
        Result.FormatAvt := CompileAvt(M, E, V, Scope);
        { a literal one is checked by Finish (an xsl:output may follow) }
        if Result.FormatAvt.IsLiteral then
          FFormatChecks.Add(Result);
        Continue;
      end;
      if (L = 'validation') and (Trim8(V) <> 'strip') and (Trim8(V) <> 'preserve') or (L = 'type') then
        Unsupported(M, E, 'a type or validation of xsl:result-document');
      if L = 'validation' then
        Continue;
      if L = 'use-character-maps' then
      begin
        if Result.MapProps = nil then
          Result.MapProps := TXsltOutputProperties.Create;
        AddMapRef(TXsltOutputProperties(Result.MapProps), M, E, V);
        Continue;
      end;
      if L = 'cdata-section-elements' then
      begin
        Result.CDataAvt := CompileAvt(M, E, V, Scope);
        if Result.CDataAvt.IsLiteral and not XsltCDataNames(LiteralOf(Result.CDataAvt), Result.ScopePrefixes,
          Result.ScopeUris, V, Bad) then
          Fail(M, E, 'XTSE0020', 'not a QName (or its prefix is not declared) in cdata-section-elements: "' +
            LandrixXmlUtf8ToString(Bad) + '"');
        Continue;
      end;
      if L = 'output-version' then
        Name := 'version'
      else
        Name := L;
      if (L = 'name') or (L = 'version') or
        (XsltOutputPropertyStatus(Name, 'yes') = xosUnknown) then
      begin
        { forwards compatible: an unknown attribute is ignored }
        if not Forwards(M, E) then
          Fail(M, E, 'XTSE0090', 'xsl:result-document has no attribute ' + LandrixXmlUtf8ToString(L));
        Continue;
      end;
      A := CompileAvt(M, E, V, Scope);
      V := LiteralOf(A);
      if A.IsLiteral then
        case XsltOutputPropertyStatus(Name, Trim8(V)) of
          xosUnsupported:
            Unsupported(M, E, 'xsl:result-document ' + LandrixXmlUtf8ToString(L) + '="' +
              LandrixXmlUtf8ToString(Trim8(V)) + '"');
          xosInvalid:
            Fail(M, E, 'XTSE0020', 'xsl:result-document ' + LandrixXmlUtf8ToString(L) + '="' +
              LandrixXmlUtf8ToString(V) + '" is not a valid value');
        else
          { supported (the run checks it again) }
        end;
      N := Integer(Length(Result.OutputNames));
      SetLength(Result.OutputNames, N + 1);
      SetLength(Result.OutputAvts, N + 1);
      Result.OutputNames[N] := Name;
      Result.OutputAvts[N] := A;
    end;
    CompileBody(M, E, Scope, Result.Body, -1);
  except
    Result.Free;
    raise;
  end;
end;

{ a yes/no attribute (also true/false and 1/0, as Saxon accepts them;
  absent: no) }
function TCompiler.YesNoAttr(M: TModule; E: Integer; const Local: TLandrixXmlUtf8): Boolean;
var
  V: TLandrixXmlUtf8;
begin
  Result := False;
  if not Attr(M, E, Local, V) then
    Exit;
  V := Trim8(V);
  if (V = 'yes') or (V = 'true') or (V = '1') then
    Result := True
  else if (V <> 'no') and (V <> 'false') and (V <> '0') then
    Fail(M, E, 'XTSE0020', LandrixXmlUtf8ToString(Local) + '="' + LandrixXmlUtf8ToString(V) +
      '" is neither yes nor no');
end;

procedure TCompiler.CompileWithParams(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
var
  C, I: Integer;
  P: TXsltWithParam;
begin
  C := M.Tree.FirstChild(E);
  while C >= 0 do
  begin
    if IsXsl(M, C, 'with-param') then
    begin
      P := TXsltWithParam.Create;
      Instr.Params.Add(P);
      P.BaseUri := StaticBase(M, C);
      P.Name := DeclName(M, C, ReqAttr(M, C, 'name'));
      P.Tunnel := YesNoAttr(M, C, 'tunnel');
      for I := 0 to Integer(Instr.Params.Count) - 2 do
        if TXsltWithParam(Instr.Params[I]).Name = P.Name then
          Fail(M, C, 'XTSE0670', 'two xsl:with-param with the name ' + LandrixXmlUtf8ToString(P.Name));
      P.Select := CompileAttr(M, C, 'select', Scope);
      P.HasAs := ParseType(M, C, Scope, P.AsType);
      if P.Select = nil then
        CompileBody(M, C, Scope, P.Body, -1)
      else
        CheckSelectOnly(M, C, 'XTSE0620');
    end
    else if IsXsl(M, C, 'sort') and (Instr.Kind = xskApplyTemplates) then
      CompileSortKey(M, C, Scope, Instr)
    else if IsXsl(M, C, 'fallback') and (Instr.Kind = xskNextMatch) then
      { only for an instruction that is not available }
    else if (M.Tree.Kind[C] = xnkElement) or
      ((M.Tree.Kind[C] = xnkText) and (Trim8(M.Tree.ValueUtf8(C)) <> '')) then
      Fail(M, C, 'XTSE0010', 'only xsl:with-param is allowed here');
    C := M.Tree.NextSibling[C];
  end;
end;

const
  CodepointCollation = 'http://www.w3.org/2005/xpath-functions/collation/codepoint';

function XsltCollationKind(const Uri: TLandrixXmlUtf8): Integer;

  function Starts(const Prefix: TLandrixXmlUtf8): Boolean;
  begin
    Result := Copy(Uri, 1, Length(Prefix)) = Prefix;
  end;

begin
  if Uri = CodepointCollation then
    Result := 0
  else if (Uri = 'http://www.w3.org/2013/collation/UCA') or Starts('http://www.w3.org/2013/collation/UCA?') or
    (Uri = 'http://saxon.sf.net/collation') or Starts('http://saxon.sf.net/collation?') or
    (Uri = 'http://www.w3.org/2005/xpath-functions/collation/html-ascii-case-insensitive') then
    Result := 1
  else
    Result := 2;
end;

{ a collation attribute (literal, after trimming; resolved against the
  static base URI): XTDE1035 (xsl:sort), XTDE1110 (xsl:for-each-group)
  or XTSE1210 (xsl:key) for an unknown one (Saxon raises the dynamic ones
  when compiling too) }
procedure CheckCollation(C: TCompiler; M: TModule; E: Integer; const V, Code: TLandrixXmlUtf8);
begin
  case XsltCollationKind(LandrixXmlXPathResolveUri(V, C.StaticBase(M, E))) of
    1:
      C.Unsupported(M, E, 'a collation other than the codepoint collation');
    2:
      C.Fail(M, E, LandrixXmlUtf8ToString(Code), 'the collation "' + LandrixXmlUtf8ToString(V) + '" is not known');
  end;
end;

{ the value of an attribute value template without expressions }
function AvtLiteral(A: TXsltAvt; out Value: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Value := '';
  Result := (A <> nil) and A.IsLiteral;
  if Result then
    for I := 0 to Integer(Length(A.Parts)) - 1 do
      Value := Value + A.Parts[I];
end;

{ xsl:sort E, a sort key of Instr: select or a sequence constructor (the
  context item by default); order, data-type, case-order and collation
  as attribute value templates, checked here where they are literal;
  lang is not supported (it needs a collation of the language), stable
  only on the first key, and the sort is always stable }
procedure TCompiler.CompileSortKey(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
var
  K: TXsltSortKey;
  V, Literal: TLandrixXmlUtf8;
  C: Integer;
  HasContent: Boolean;
begin
  if Instr.SortKeys = nil then
    Instr.SortKeys := TObjectList.Create;
  K := TXsltSortKey.Create;
  Instr.SortKeys.Add(K);
  K.Where := NewInstr(xskText, M, E);
  HasContent := False;
  C := M.Tree.FirstChild(E);
  while C >= 0 do
  begin
    { white space text kept by xml:space is content as well }
    if (M.Tree.Kind[C] = xnkElement) or (M.Tree.Kind[C] = xnkText) and
      ((Trim8(M.Tree.ValueUtf8(C)) <> '') or PreservesSpace(M.Tree, C)) then
      HasContent := True;
    C := M.Tree.NextSibling[C];
  end;
  K.Select := CompileAttr(M, E, 'select', Scope);
  if (K.Select <> nil) and HasContent then
    Fail(M, E, 'XTSE1015', 'xsl:sort has a select attribute and content');
  if HasContent then
    CompileBody(M, E, Scope, K.Body, -1)
  else if K.Select = nil then
    K.Select := Compile(M, E, '.', Scope);
  if Attr(M, E, 'order', V) then
  begin
    K.Order := CompileAvt(M, E, V, Scope);
    if AvtLiteral(K.Order, V) and (Trim8(V) <> 'ascending') and (Trim8(V) <> 'descending') then
      Fail(M, E, 'XTSE0020', 'xsl:sort order is ascending or descending');
  end;
  if Attr(M, E, 'case-order', V) then
  begin
    K.CaseOrder := CompileAvt(M, E, V, Scope);
    if AvtLiteral(K.CaseOrder, V) and (Trim8(V) <> 'upper-first') and (Trim8(V) <> 'lower-first') then
      Fail(M, E, 'XTSE0020', 'xsl:sort case-order is upper-first or lower-first');
  end;
  if Attr(M, E, 'data-type', V) then
  begin
    K.DataType := CompileAvt(M, E, V, Scope);
    if AvtLiteral(K.DataType, V) and (Trim8(V) <> 'text') and (Trim8(V) <> 'number') then
    begin
      if Pos8(':', V) > 0 then
        Unsupported(M, E, 'a data-type of xsl:sort with a prefix')
      else
        Fail(M, E, 'XTSE0020', 'xsl:sort data-type is text, number or a prefixed name');
    end;
  end;
  if Attr(M, E, 'lang', V) then
    Unsupported(M, E, 'xsl:sort with lang');
  if Attr(M, E, 'collation', V) then
  begin
    K.Collation := CompileAvt(M, E, V, Scope);
    if AvtLiteral(K.Collation, V) then
      CheckCollation(Self, M, E, Trim8(V), 'XTDE1035');
  end;
  if Attr(M, E, 'stable', V) then
  begin
    if Instr.SortKeys.Count > 1 then
      Fail(M, E, 'XTSE1017', 'stable is allowed on the first xsl:sort only');
    K.Stable := CompileAvt(M, E, V, Scope);
    if AvtLiteral(K.Stable, Literal) and (Trim8(Literal) <> 'yes') and (Trim8(Literal) <> 'no') then
      Fail(M, E, 'XTSE0020', 'xsl:sort stable is yes or no');
  end;
end;

{ xsl:analyze-string: select, regex and flags (a literal regex and flags
  are checked here: XTDE1140, XTDE1145, XTDE1150 for one that matches the
  empty string), then xsl:matching-substring and xsl:non-matching-substring
  in this order, at least one of them (XTSE1130), and xsl:fallback }
procedure TCompiler.CompileAnalyzeString(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
var
  V, Pattern, Flags: TLandrixXmlUtf8;
  C: Integer;
  HasMatching, HasNonMatching: Boolean;
  R: TLandrixXmlRegex;
begin
  Instr.Select := Compile(M, E, ReqAttr(M, E, 'select'), Scope);
  Instr.RegexAvt := CompileAvt(M, E, ReqAttr(M, E, 'regex'), Scope);
  if Attr(M, E, 'flags', V) then
    Instr.FlagsAvt := CompileAvt(M, E, V, Scope);
  Flags := '';
  if AvtLiteral(Instr.RegexAvt, Pattern) and ((Instr.FlagsAvt = nil) or AvtLiteral(Instr.FlagsAvt, Flags)) then
  begin
    if not LandrixXmlRegexFlagsValid(Flags, xrmXPath) then
      Fail(M, E, 'XTDE1145', 'invalid regular expression flags "' + LandrixXmlUtf8ToString(Flags) + '"');
    R := nil;
    try
      try
        R := TLandrixXmlRegex.Create(Pattern, xrmXPath, Flags);
      except
        on X: ELandrixXmlError do
          if X.Code = xecRegex then
            Fail(M, E, 'XTDE1140', 'invalid regular expression: ' + X.Message)
          else
            raise;
      end;
      { Saxon difference: analyze-string-empty-match }
      if R.MatchesEmptyString then
        Fail(M, E, 'XTDE1150', 'the regular expression matches a zero-length string');
    finally
      R.Free;
    end;
  end;
  HasMatching := False;
  HasNonMatching := False;
  C := M.Tree.FirstChild(E);
  while C >= 0 do
  begin
    if IsXsl(M, C, 'matching-substring') and not HasMatching and not HasNonMatching then
    begin
      HasMatching := True;
      CompileBody(M, C, Scope, Instr.Body, -1);
    end
    else if IsXsl(M, C, 'non-matching-substring') and not HasNonMatching then
    begin
      HasNonMatching := True;
      Instr.NonMatching := TObjectList.Create;
      CompileBody(M, C, Scope, Instr.NonMatching, -1);
    end
    else if IsXsl(M, C, 'fallback') then
      { for an XSLT 1.0 processor only }
    else if (M.Tree.Kind[C] = xnkElement) or (M.Tree.Kind[C] = xnkText) and
      (Trim8(M.Tree.ValueUtf8(C)) <> '') then
      Fail(M, C, 'XTSE0010', 'xsl:analyze-string contains xsl:matching-substring, ' +
        'xsl:non-matching-substring and xsl:fallback, in this order');
    C := M.Tree.NextSibling[C];
  end;
  if not HasMatching and not HasNonMatching then
    Fail(M, E, 'XTSE1130', 'xsl:analyze-string needs xsl:matching-substring or xsl:non-matching-substring');
end;

{ whether an xsl:sort comes after C among its siblings before any other
  element or text that is not white space }
function TCompiler.SortFollows(M: TModule; C: Integer): Boolean;
begin
  Result := False;
  C := M.Tree.NextSibling[C];
  while C >= 0 do
  begin
    if IsXsl(M, C, 'sort') then
    begin
      Result := True;
      Exit;
    end;
    if (M.Tree.Kind[C] = xnkElement) or (M.Tree.Kind[C] = xnkText) and (Trim8(M.Tree.ValueUtf8(C)) <> '') then
      Exit;
    C := M.Tree.NextSibling[C];
  end;
end;

{ the xsl:sort children at the start of E as sort keys of Instr; the
  first child after them (-2 if there is none) }
function TCompiler.CompileSorts(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr): Integer;
var
  C: Integer;
begin
  C := M.Tree.FirstChild(E);
  while C >= 0 do
  begin
    if IsXsl(M, C, 'sort') then
      CompileSortKey(M, C, Scope, Instr)
    else if (M.Tree.Kind[C] = xnkElement) or (M.Tree.Kind[C] = xnkText) and
      (Trim8(M.Tree.ValueUtf8(C)) <> '') then
      Break
    else if (M.Tree.Kind[C] = xnkText) and PreservesSpace(M.Tree, C) and not SortFollows(M, C) then
      { white space kept by xml:space after the last xsl:sort: content
        (before an xsl:sort it is dropped, as Saxon does) }
      Break;
    C := M.Tree.NextSibling[C];
  end;
  Result := C;
  if Result < 0 then
    Result := -2;
end;

function TCompiler.CompileVariable(M: TModule; E: Integer; Scope: TScope; Param: Boolean): TXsltInstr;
var
  Lexical, V: TLandrixXmlUtf8;
begin
  Result := NewInstr(xskVariable, M, E);
  try
    Result.IsParam := Param;
    Lexical := Trim8(ReqAttr(M, E, 'name'));
    Result.VarName := DeclName(M, E, Lexical);
    if Param then
    begin
      Result.Required := Attr(M, E, 'required', V) and (V = 'yes');
      Result.Tunnel := YesNoAttr(M, E, 'tunnel');
    end;
    Result.Select := CompileAttr(M, E, 'select', Scope);
    Result.HasAs := ParseType(M, E, Scope, Result.AsType);
    if Result.Select = nil then
      CompileBody(M, E, Scope, Result.Body, -1)
    else
      CheckSelectOnly(M, E, 'XTSE0620');
    { visible after the declaration }
    Result.Slot := Scope.NextSlot;
    Inc(Scope.NextSlot);
    if Scope.NextSlot > Scope.MaxSlot then
      Scope.MaxSlot := Scope.NextSlot;
    Scope.Add(Lexical, Result.VarName, Result.Slot);
  except
    Result.Free;
    raise;
  end;
end;

{ an element with a select attribute must be empty (white space that
  xml:space keeps counts; comments and processing instructions do not):
  Code is the error code of the element; xsl:sequence may hold
  xsl:fallback (XSLT 3.0, as Saxon) }
procedure TCompiler.CheckSelectOnly(M: TModule; E: Integer; const Code: string);
var
  C: Integer;
begin
  C := M.Tree.FirstChild(E);
  while C >= 0 do
  begin
    if ((M.Tree.Kind[C] = xnkElement) and not ((Code = 'XTSE3185') and IsXsl(M, C, 'fallback'))) or
      (M.Tree.Kind[C] = xnkText) and ((Trim8(M.Tree.ValueUtf8(C)) <> '') or PreservesSpace(M.Tree, C)) then
      Fail(M, E, Code, DisplayName(M, E) + ' with a select attribute must be empty');
    C := M.Tree.NextSibling[C];
  end;
end;

{ xsl:iterate (XSLT 3.0): select, the parameters (each with a value: no
  required, no tunnel, XTSE3520 for one that would need a value), the
  xsl:on-completion after them (without the focus; it sees the
  parameters, not the variables of the body), then the body }
procedure TCompiler.CompileIterate(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
var
  C, D, I, SavedCount: Integer;
  P, W: TXsltInstr;
  V, S: TLandrixXmlUtf8;
  Started: Boolean;
begin
  Instr.Select := Compile(M, E, ReqAttr(M, E, 'select'), Scope);
  SavedCount := Scope.Count;
  try
    Started := False;
    C := M.Tree.FirstChild(E);
    while C >= 0 do
    begin
      if IsXsl(M, C, 'param') then
      begin
        if Started then
          Fail(M, C, 'XTSE0010', 'the xsl:param elements of xsl:iterate come first');
        if YesNoAttr(M, C, 'tunnel') then
          Fail(M, C, 'XTSE0020', 'a parameter of xsl:iterate cannot be a tunnel parameter');
        if Attr(M, C, 'static', V) then
          Fail(M, C, 'XTSE0090', 'a parameter of xsl:iterate has no attribute static');
        P := CompileVariable(M, C, Scope, True);
        Instr.Branches.Add(P);
        { yes, true or 1 (XTSE0020 for another value) }
        P.Required := YesNoAttr(M, C, 'required');
        { required="yes" (XTDE0700 when it runs, as in Saxon) without a value }
        if P.Required and ((P.Select <> nil) or (P.Body.Count > 0)) then
          Fail(M, C, 'XTSE0010', 'a required parameter has no value');
        for I := 0 to Integer(Instr.Branches.Count) - 2 do
          if TXsltInstr(Instr.Branches[I]).VarName = P.VarName then
            Fail(M, C, 'XTSE0580', 'two parameters of xsl:iterate have the same name');
        if not P.Required and P.HasAs and (P.Select = nil) and (P.Body.Count = 0) and (P.AsType.Kind <> xtkEmpty) and
          not (P.AsType.Occurrence in [xocOptional, xocMany]) then
          Fail(M, C, 'XTSE3520', 'the parameter ' + LandrixXmlUtf8ToString(P.VarName) +
            ' of xsl:iterate needs an initial value: its type does not allow the empty sequence');
      end
      else if IsXsl(M, C, 'on-completion') then
      begin
        if Started then
          Fail(M, C, 'XTSE0010', 'xsl:on-completion comes first in xsl:iterate after the xsl:param elements');
        Started := True;
        W := NewInstr(xskSequence, M, C);
        Instr.Completion := W;
        W.Select := CompileAttr(M, C, 'select', Scope);
        if W.Select = nil then
          CompileBody(M, C, Scope, W.Body, -1)
        else if HasContent(M, C) then
          Fail(M, C, 'XTSE3125', 'xsl:on-completion with a select attribute must be empty');
      end
      else if M.Tree.Kind[C] = xnkElement then
        Break
      else if M.Tree.Kind[C] = xnkText then
      begin
        { the text up to the next element (comments and processing
          instructions between): content if it is not white space, or
          white space xml:space keeps that no declaration follows }
        S := '';
        D := C;
        while (D >= 0) and (M.Tree.Kind[D] in [xnkText, xnkComment, xnkProcessingInstruction]) do
        begin
          if M.Tree.Kind[D] = xnkText then
            S := S + M.Tree.ValueUtf8(D);
          D := M.Tree.NextSibling[D];
        end;
        if (Trim8(S) <> '') or PreservesSpace(M.Tree, C) and not ((D >= 0) and (IsXsl(M, D, 'param') or
          IsXsl(M, D, 'on-completion'))) then
          Break;
      end;
      C := M.Tree.NextSibling[C];
    end;
    if C >= 0 then
    begin
      FIterates.Add(Instr);
      try
        CompileBody(M, E, Scope, Instr.Body, C);
      finally
        FIterates.Delete(FIterates.Count - 1);
      end;
    end;
  finally
    { the parameters are not visible after xsl:iterate }
    Scope.Count := SavedCount;
  end;
end;

{ xsl:break and xsl:next-iteration in a tail position of the body of an
  xsl:iterate, checked as Saxon checks it (XTSE3120 also outside
  xsl:iterate, where XTSE0010 would do too): the nearest ancestor other
  than xsl:if, xsl:choose, xsl:when and xsl:otherwise is xsl:iterate, and
  it is the last instruction of its parent (xsl:fallback aside), the
  xsl:if or xsl:choose around it likewise up to the xsl:iterate }
procedure TCompiler.CheckTail(M: TModule; E: Integer);
var
  P, N, A: Integer;
  L: string;
begin
  L := DisplayName(M, E);
  P := M.Tree.Parent[E];
  while IsXsl(M, P, 'if') or IsXsl(M, P, 'choose') or IsXsl(M, P, 'when') or IsXsl(M, P, 'otherwise') do
    P := M.Tree.Parent[P];
  if not IsXsl(M, P, 'iterate') then
    Fail(M, E, 'XTSE3120', L + ' is not allowed within ' + DisplayName(M, P));
  N := E;
  while True do
  begin
    A := M.Tree.NextSibling[N];
    while A >= 0 do
    begin
      if (M.Tree.Kind[A] = xnkElement) and not IsXsl(M, A, 'fallback') or (M.Tree.Kind[A] = xnkText) and
        ((Trim8(M.Tree.ValueUtf8(A)) <> '') or PreservesSpace(M.Tree, A)) then
        Fail(M, E, 'XTSE3120', L + ' must be the last instruction of the xsl:iterate body');
      A := M.Tree.NextSibling[A];
    end;
    P := M.Tree.Parent[N];
    if IsXsl(M, P, 'iterate') then
      Exit;
    if IsXsl(M, P, 'if') then
      N := P
    else if IsXsl(M, P, 'when') or IsXsl(M, P, 'otherwise') then
      N := M.Tree.Parent[P]
    else
      Fail(M, E, 'XTSE3120', L + ' must be the last instruction of the xsl:iterate body');
  end;
end;

{ xsl:next-iteration: its xsl:with-param elements set parameters of the
  xsl:iterate around it (XTSE3130 for another name), no tunnel ones }
procedure TCompiler.CompileNextIteration(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
var
  I, J: Integer;
  P: TXsltWithParam;
  It: TXsltInstr;
begin
  CompileWithParams(M, E, Scope, Instr);
  It := TXsltInstr(FIterates[FIterates.Count - 1]);
  for I := 0 to Integer(Instr.Params.Count) - 1 do
  begin
    P := TXsltWithParam(Instr.Params[I]);
    if P.Tunnel then
      Fail(M, E, 'XTSE0020', 'xsl:with-param in xsl:next-iteration cannot be a tunnel parameter');
    for J := 0 to Integer(It.Branches.Count) - 1 do
      if TXsltInstr(It.Branches[J]).VarName = P.Name then
        P.Target := TXsltInstr(It.Branches[J]);
    if P.Target = nil then
      Fail(M, E, 'XTSE3130', 'the xsl:iterate has no parameter ' + LandrixXmlUtf8ToString(P.Name));
  end;
end;

procedure ScopeNamespaces(M: TModule; E: Integer; Instr: TXsltInstr);
var
  Prefixes: TLandrixXmlUtf8Array;
  Uri: TLandrixXmlUtf8;
  I: Integer;
begin
  Prefixes := M.Tree.InScopePrefixesUtf8(E);
  for I := 0 to Integer(Length(Prefixes)) - 1 do
    if M.Tree.LookupNamespace(E, Prefixes[I], Uri) then
    begin
      SetLength(Instr.ScopePrefixes, Length(Instr.ScopePrefixes) + 1);
      SetLength(Instr.ScopeUris, Length(Instr.ScopeUris) + 1);
      Instr.ScopePrefixes[High(Instr.ScopePrefixes)] := Prefixes[I];
      Instr.ScopeUris[High(Instr.ScopeUris)] := Uri;
    end;
end;

function TCompiler.CompileInstr(M: TModule; E: Integer; Scope: TScope): TXsltInstr;
var
  L, V: TLandrixXmlUtf8;
  C: Integer;
  W: TXsltInstr;
  HasOtherwise: Boolean;
begin
  L := M.Tree.LocalNameUtf8(E);
  Result := nil;
  if L = 'variable' then
  begin
    Result := CompileVariable(M, E, Scope, False);
    Exit;
  end;
  if (L = 'param') or (L = 'with-param') or (L = 'when') or (L = 'otherwise') then
    Fail(M, E, 'XTSE0010', 'xsl:' + LandrixXmlUtf8ToString(L) + ' is not allowed here');
  { the places xsl:sort may have are compiled by CompileSorts }
  if L = 'sort' then
    Fail(M, E, 'XTSE0010', 'xsl:sort is not allowed here');
  if L = 'fallback' then
    Exit;
  if (L = 'matching-substring') or (L = 'non-matching-substring') then
    Fail(M, E, 'XTSE0010', 'xsl:' + LandrixXmlUtf8ToString(L) + ' is allowed in xsl:analyze-string only');
  if (L = 'try') or
    (L = 'evaluate') or (L = 'where-populated') or (L = 'on-empty') or
    (L = 'on-non-empty') or (L = 'map') or (L = 'array') or (L = 'merge') or (L = 'fork') or
    (L = 'assert') or (L = 'source-document') or
    (L = 'call-function') or (L = 'context-item') then
    Unsupported(M, E, 'xsl:' + LandrixXmlUtf8ToString(L));
  { XSLT 3.0, also in a stylesheet of version 2.0 (as Saxon runs it) }
  if (L = 'break') or (L = 'next-iteration') then
    CheckTail(M, E);
  try
    if L = 'iterate' then
    begin
      Result := NewInstr(xskIterate, M, E);
      CompileIterate(M, E, Scope, Result);
    end
    else if L = 'break' then
    begin
      Result := NewInstr(xskBreak, M, E);
      Result.Select := CompileAttr(M, E, 'select', Scope);
      if Result.Select = nil then
        CompileBody(M, E, Scope, Result.Body, -1)
      else if HasContent(M, E) then
        Fail(M, E, 'XTSE3125', 'xsl:break with a select attribute must be empty');
    end
    else if L = 'next-iteration' then
    begin
      Result := NewInstr(xskNextIteration, M, E);
      CompileNextIteration(M, E, Scope, Result);
    end
    else if L = 'text' then
    begin
      Result := NewInstr(xskText, M, E);
      C := M.Tree.FirstChild(E);
      while C >= 0 do
      begin
        if M.Tree.Kind[C] = xnkText then
          Result.Text := Result.Text + M.Tree.ValueUtf8(C)
        else if M.Tree.Kind[C] = xnkElement then
          Fail(M, C, 'XTSE0010', 'xsl:text contains text only');
        C := M.Tree.NextSibling[C];
      end;
      Result.NoEscape := NoEscape(M, E);
      if ExpandText(M, E) then
        CompileText(M, E, Result, Scope);
    end
    else if L = 'value-of' then
    begin
      Result := NewInstr(xskValueOf, M, E);
      Result.Select := CompileAttr(M, E, 'select', Scope);
      if Attr(M, E, 'separator', V) then
        Result.Separator := CompileAvt(M, E, V, Scope);
      Result.NoEscape := NoEscape(M, E);
      if Result.Select = nil then
        CompileBody(M, E, Scope, Result.Body, -1)
      else
        CheckSelectOnly(M, E, 'XTSE0870');
    end
    else if L = 'apply-templates' then
    begin
      Result := NewInstr(xskApplyTemplates, M, E);
      if Attr(M, E, 'select', V) then
        Result.Select := Compile(M, E, V, Scope)
      else
      begin
        Result.Select := Compile(M, E, 'child::node()', Scope);
        Result.ImplicitSelect := True;
      end;
      { none: the default mode; an empty one is XTSE0020 (Saxon) }
      if not Attr(M, E, 'mode', V) then
        V := '#default';
      V := Trim8(V);
      if V = '#current' then
        Result.CurrentMode := True
      else if V = '#default' then
        Result.Mode := ModeOf(DefaultModeOf(M, E))
      else if V = '#unnamed' then
        Result.Mode := ModeOf('')
      else
      begin
        if (V = '') or (Pos8(' ', Collapse8(V)) > 0) then
          Fail(M, E, 'XTSE0020', 'not a mode name: "' + LandrixXmlUtf8ToString(V) + '"');
        Result.Mode := ModeOf(ModeName(M, E, V));
      end;
      CompileWithParams(M, E, Scope, Result);
    end
    else if L = 'result-document' then
      Result := CompileResultDocument(M, E, Scope)
    else if (L = 'next-match') or (L = 'apply-imports') then
    begin
      if L = 'next-match' then
        Result := NewInstr(xskNextMatch, M, E)
      else
        Result := NewInstr(xskApplyImports, M, E);
      CompileWithParams(M, E, Scope, Result);
    end
    else if L = 'call-template' then
    begin
      Result := NewInstr(xskCallTemplate, M, E);
      { resolved by Finish }
      Result.VarName := QNameToClark(M, E, ReqAttr(M, E, 'name'), False);
      CompileWithParams(M, E, Scope, Result);
    end
    else if L = 'if' then
    begin
      Result := NewInstr(xskIf, M, E);
      Result.Test := Compile(M, E, ReqAttr(M, E, 'test'), Scope);
      CompileBody(M, E, Scope, Result.Body, -1);
    end
    else if L = 'choose' then
    begin
      Result := NewInstr(xskChoose, M, E);
      HasOtherwise := False;
      C := M.Tree.FirstChild(E);
      while C >= 0 do
      begin
        if IsXsl(M, C, 'when') then
        begin
          if HasOtherwise then
            Fail(M, C, 'XTSE0010', 'xsl:when after xsl:otherwise');
          W := NewInstr(xskWhen, M, C);
          Result.Branches.Add(W);
          W.Test := Compile(M, C, ReqAttr(M, C, 'test'), Scope);
          CompileBody(M, C, Scope, W.Body, -1);
        end
        else if IsXsl(M, C, 'otherwise') then
        begin
          if HasOtherwise then
            Fail(M, C, 'XTSE0010', 'xsl:choose has one xsl:otherwise, after the xsl:when elements');
          HasOtherwise := True;
          CompileBody(M, C, Scope, Result.Body, -1);
        end
        else if (M.Tree.Kind[C] = xnkElement) or
          ((M.Tree.Kind[C] = xnkText) and (Trim8(M.Tree.ValueUtf8(C)) <> '')) then
          Fail(M, C, 'XTSE0010', 'xsl:choose contains xsl:when and xsl:otherwise only');
        C := M.Tree.NextSibling[C];
      end;
      if Result.Branches.Count = 0 then
        Fail(M, E, 'XTSE0010', 'xsl:choose needs an xsl:when');
    end
    else if L = 'for-each' then
    begin
      Result := NewInstr(xskForEach, M, E);
      Result.Select := Compile(M, E, ReqAttr(M, E, 'select'), Scope);
      C := CompileSorts(M, E, Scope, Result);
      if C >= 0 then
        CompileBody(M, E, Scope, Result.Body, C);
    end
    else if L = 'analyze-string' then
    begin
      Result := NewInstr(xskAnalyzeString, M, E);
      CompileAnalyzeString(M, E, Scope, Result);
    end
    else if L = 'perform-sort' then
    begin
      { the sorted sequence: select, or the sequence constructor after the
        sort keys }
      Result := NewInstr(xskPerformSort, M, E);
      Result.Select := CompileAttr(M, E, 'select', Scope);
      C := CompileSorts(M, E, Scope, Result);
      if Result.SortKeys = nil then
        Fail(M, E, 'XTSE0010', 'xsl:perform-sort needs an xsl:sort');
      if C >= 0 then
      begin
        if Result.Select <> nil then
        begin
          while C >= 0 do
          begin
            if not IsXsl(M, C, 'fallback') and ((M.Tree.Kind[C] = xnkElement) or
              (M.Tree.Kind[C] = xnkText) and (Trim8(M.Tree.ValueUtf8(C)) <> '')) then
              Fail(M, C, 'XTSE1040', 'xsl:perform-sort with select has xsl:sort and xsl:fallback only');
            C := M.Tree.NextSibling[C];
          end;
        end
        else
          CompileBody(M, E, Scope, Result.Body, C);
      end;
    end
    else if L = 'number' then
    begin
      Result := NewInstr(xskNumber, M, E);
      CompileNumber(M, E, Scope, Result);
    end
    else if L = 'for-each-group' then
    begin
      Result := NewInstr(xskForEachGroup, M, E);
      CompileGroup(M, E, Scope, Result);
    end
    else if L = 'sequence' then
    begin
      Result := NewInstr(xskSequence, M, E);
      Result.Select := Compile(M, E, ReqAttr(M, E, 'select'), Scope);
      { xsl:fallback is allowed here (XSLT 3.0), as in Saxon }
      CheckSelectOnly(M, E, 'XTSE3185');
    end
    else if L = 'copy-of' then
    begin
      Result := NewInstr(xskCopyOf, M, E);
      Result.Select := Compile(M, E, ReqAttr(M, E, 'select'), Scope);
      CheckSelectOnly(M, E, 'XTSE0260');
      Result.NoNamespaces := Attr(M, E, 'copy-namespaces', V) and not YesNoAttr(M, E, 'copy-namespaces');
    end
    else if L = 'copy' then
    begin
      Result := NewInstr(xskCopy, M, E);
      Result.NoNamespaces := Attr(M, E, 'copy-namespaces', V) and not YesNoAttr(M, E, 'copy-namespaces');
      if Attr(M, E, 'use-attribute-sets', V) then
        Result.UseSets := UseAttributeSets(M, E, V);
      CompileBody(M, E, Scope, Result.Body, -1);
    end
    else if (L = 'element') or (L = 'attribute') then
    begin
      if L = 'element' then
        Result := NewInstr(xskElement, M, E)
      else
        Result := NewInstr(xskAttribute, M, E);
      Result.NameAvt := CompileAvt(M, E, ReqAttr(M, E, 'name'), Scope);
      if Attr(M, E, 'namespace', V) then
        Result.NamespaceAvt := CompileAvt(M, E, V, Scope);
      if Attr(M, E, 'use-attribute-sets', V) then
      begin
        if L <> 'attribute' then
          Result.UseSets := UseAttributeSets(M, E, V)
        else if not Forwards(M, E) then
          Fail(M, E, 'XTSE0090', 'xsl:attribute has no attribute use-attribute-sets');
      end;
      ScopeNamespaces(M, E, Result);
      if L = 'attribute' then
      begin
        Result.Select := CompileAttr(M, E, 'select', Scope);
        if Attr(M, E, 'separator', V) then
          Result.Separator := CompileAvt(M, E, V, Scope);
        if Attr(M, E, 'type', V) or Attr(M, E, 'validation', V) and (V <> 'strip') and (V <> 'preserve') then
          Unsupported(M, E, 'a type or validation of xsl:attribute');
      end;
      if Result.Select = nil then
        CompileBody(M, E, Scope, Result.Body, -1)
      else
        CheckSelectOnly(M, E, 'XTSE0840');
    end
    else if L = 'namespace' then
    begin
      Result := NewInstr(xskNamespace, M, E);
      Result.NameAvt := CompileAvt(M, E, ReqAttr(M, E, 'name'), Scope);
      Result.Select := CompileAttr(M, E, 'select', Scope);
      if Result.Select = nil then
        CompileBody(M, E, Scope, Result.Body, -1)
      else
        CheckSelectOnly(M, E, 'XTSE0910');
    end
    else if L = 'comment' then
    begin
      Result := NewInstr(xskComment, M, E);
      Result.Select := CompileAttr(M, E, 'select', Scope);
      if Result.Select = nil then
        CompileBody(M, E, Scope, Result.Body, -1)
      else
        CheckSelectOnly(M, E, 'XTSE0940');
    end
    else if L = 'processing-instruction' then
    begin
      Result := NewInstr(xskProcessingInstruction, M, E);
      Result.NameAvt := CompileAvt(M, E, ReqAttr(M, E, 'name'), Scope);
      Result.Select := CompileAttr(M, E, 'select', Scope);
      if Result.Select = nil then
        CompileBody(M, E, Scope, Result.Body, -1)
      else
        CheckSelectOnly(M, E, 'XTSE0880');
    end
    else if L = 'message' then
    begin
      Result := NewInstr(xskMessage, M, E);
      if Attr(M, E, 'terminate', V) then
      begin
        { a fixed value is checked here (after the template syntax), a
          computed one when it is used }
        Result.NameAvt := CompileAvt(M, E, V, Scope);
        if Pos8('{', V) = 0 then
          YesNoAttr(M, E, 'terminate');
      end;
      Result.Select := CompileAttr(M, E, 'select', Scope);
      CompileBody(M, E, Scope, Result.Body, -1);
    end
    else if L = 'document' then
    begin
      Result := NewInstr(xskDocument, M, E);
      CompileBody(M, E, Scope, Result.Body, -1);
    end
    else if Forwards(M, E) and not XsltElementAvailable(L) and HasFallback(M, E) then
      { forwards compatible: an instruction of a later version runs its
        xsl:fallback (as Saxon, only with one; without, XTSE0010; its
        other children are not compiled; a known element in the wrong
        place stays XTSE0010) }
      Result := CompileExtension(M, E, Scope, False)
    else
      Fail(M, E, 'XTSE0010', 'unknown or misplaced XSLT element xsl:' + LandrixXmlUtf8ToString(L));
  except
    Result.Free;
    raise;
  end;
end;

{ --- declarations -------------------------------------------------------------- }

function TCompiler.ModeOf(const Name: TLandrixXmlUtf8): TXsltMode;
begin
  Result := FC.FindMode(Name);
  if Result <> nil then
    Exit;
  Result := TXsltMode.Create;
  Result.Name := Name;
  FC.Modes.AddObject(LandrixXmlUtf8ToKey(Name), Result);
end;

procedure TCompiler.CompileGlobals;
var
  I, J: Integer;
  D, Best: TDecl;
  G: TXsltGlobal;
  Name, Lexical: TLandrixXmlUtf8;
  Scope: TScope;
  Found: Boolean;
  V: TLandrixXmlUtf8;
  Names: TStringList;
  Decls, DupDecls: TList;
  DupIndex: array of Integer;
begin
  { the declaration of each name with the highest precedence }
  DupIndex := nil;
  Names := TXsltStringList.Create;
  Decls := TList.Create;
  DupDecls := TList.Create;
  try
    for I := 0 to Integer(FDecls.Count) - 1 do
    begin
      D := TDecl(FDecls[I]);
      if not (IsXsl(D.Module, D.Element, 'variable') or IsXsl(D.Module, D.Element, 'param')) then
        Continue;
      Name := DeclName(D.Module, D.Element, ReqAttr(D.Module, D.Element, 'name'));
      Found := False;
      for J := 0 to Integer(Names.Count) - 1 do
        if Names[J] = LandrixXmlUtf8ToKey(Name) then
        begin
          Found := True;
          Best := TDecl(Decls[J]);
          { XTSE0630 only if no declaration of higher precedence
            overrides the two (checked below) }
          if Best.Precedence = D.Precedence then
          begin
            SetLength(DupIndex, Length(DupIndex) + 1);
            DupIndex[High(DupIndex)] := J;
            DupDecls.Add(D);
          end;
          if D.Precedence > Best.Precedence then
            Decls[J] := D;
        end;
      if not Found then
      begin
        Names.Add(LandrixXmlUtf8ToKey(Name));
        Decls.Add(D);
      end;
    end;
    for I := 0 to Integer(Length(DupIndex)) - 1 do
      if TDecl(Decls[DupIndex[I]]).Precedence = TDecl(DupDecls[I]).Precedence then
        Fail(TDecl(DupDecls[I]).Module, TDecl(DupDecls[I]).Element, 'XTSE0630', 'the global variable ' +
          LandrixXmlUtf8ToString(LandrixXmlKeyToUtf8(Names[DupIndex[I]])) + ' is declared twice');
    for I := 0 to Integer(Decls.Count) - 1 do
    begin
      D := TDecl(Decls[I]);
      G := TXsltGlobal.Create;
      FC.Globals.Add(G);
      G.Name := LandrixXmlKeyToUtf8(Names[I]);
      Lexical := Trim8(ReqAttr(D.Module, D.Element, 'name'));
      G.Lexical := Lexical;
      G.Module := D.Module.Uri;
      G.BaseUri := StaticBase(D.Module, D.Element);
      G.Line := D.Module.LineOf(D.Element);
      G.Column := D.Module.ColumnOf(D.Element);
      G.Slot := I;
      G.Precedence := D.Precedence;
      G.IsParam := IsXsl(D.Module, D.Element, 'param');
      G.Required := G.IsParam and Attr(D.Module, D.Element, 'required', V) and (V = 'yes');
      if YesNoAttr(D.Module, D.Element, 'tunnel') then
        Fail(D.Module, D.Element, 'XTSE0020', 'a global parameter cannot be a tunnel parameter');
    end;
    FC.GlobalCount := Integer(FC.Globals.Count);
    { the values, now that every global has its slot }
    for I := 0 to Integer(Decls.Count) - 1 do
    begin
      D := TDecl(Decls[I]);
      G := TXsltGlobal(FC.Globals[I]);
      Scope := TScope.Create;
      try
        Scope.NextSlot := FC.GlobalCount;
        Scope.MaxSlot := FC.GlobalCount;
        G.Select := CompileAttr(D.Module, D.Element, 'select', Scope);
        G.HasAs := ParseType(D.Module, D.Element, Scope, G.AsType);
        if G.Select = nil then
          CompileBody(D.Module, D.Element, Scope, G.Body, -1)
        else
          CheckSelectOnly(D.Module, D.Element, 'XTSE0620');
        G.FrameSize := Scope.MaxSlot;
        if (G.Select = nil) and (G.Body.Count > 0) then
        begin
          { the only expression that sees the internal prefix }
          FInternalCall := True;
          try
            G.Call := Compile(D.Module, D.Element, 'xsl-internal-f:global(' +
              LandrixXmlStringToUtf8(IntToStr(G.Slot)) + ')', nil);
          finally
            FInternalCall := False;
          end;
        end;
      finally
        Scope.Free;
      end;
    end;
  finally
    DupDecls.Free;
    Decls.Free;
    Names.Free;
  end;
end;

{ an xs:decimal as written: [+-] digits [. digits] or [+-] . digits }
function IsDecimal(const S: TLandrixXmlUtf8): Boolean;
var
  I, Digits: Integer;
  Dot: Boolean;
begin
  Result := False;
  I := 1;
  if (I <= Length(S)) and (S[I] in ['+', '-']) then
    Inc(I);
  Digits := 0;
  Dot := False;
  while I <= Length(S) do
  begin
    if S[I] in ['0'..'9'] then
      Inc(Digits)
    else if (S[I] = '.') and not Dot then
      Dot := True
    else
      Exit;
    Inc(I);
  end;
  Result := Digits > 0;
end;

{ S without white space outside string literals (where it is only
  insignificant: "element (r)" is "element(r)") }
function StripSpace(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I, Depth, Start: Integer;
  Quote: AnsiChar;
begin
  Result := '';
  Quote := #0;
  I := 1;
  while I <= Length(S) do
  begin
    if Quote <> #0 then
    begin
      if S[I] = Quote then
        Quote := #0;
    end
    else if S[I] in ['''', '"'] then
      Quote := S[I]
    else if S[I] in [#9, #10, #13, ' '] then
    begin
      Inc(I);
      Continue;
    end
    { an XPath comment (nested ones too) is white space }
    else if (S[I] = '(') and (I < Length(S)) and (S[I + 1] = ':') then
    begin
      Start := I;
      Depth := 1;
      Inc(I, 2);
      while (I <= Length(S)) and (Depth > 0) do
      begin
        if (S[I] = '(') and (I < Length(S)) and (S[I + 1] = ':') then
        begin
          Inc(Depth);
          Inc(I);
        end
        else if (S[I] = ':') and (I < Length(S)) and (S[I + 1] = ')') then
        begin
          Dec(Depth);
          Inc(I);
        end;
        Inc(I);
      end;
      { an unclosed comment stays, for the parser to reject }
      if Depth > 0 then
      begin
        Result := Result + Copy(S, Start, MaxInt);
        Exit;
      end;
      Continue;
    end;
    Result := Result + Copy(S, I, 1);
    Inc(I);
  end;
end;

{ the default priority of a pattern branch (XSLT 2.0, 6.4; XSLT 3.0, 6.6) }
function DefaultPriority(const Branch: TLandrixXmlUtf8): Double;
var
  S, Test: TLandrixXmlUtf8;
  I: Integer;

  function IsNCName(const N: TLandrixXmlUtf8): Boolean;
  begin
    Result := IsNCName8(N);
  end;

  function IsQName(const N: TLandrixXmlUtf8): Boolean;
  var
    K: Integer;
  begin
    K := Pos8(':', N);
    if K = 0 then
      Result := IsNCName(N)
    else
      Result := IsNCName(Copy(N, 1, K - 1)) and IsNCName(Copy(N, K + 1, Length(N) - K));
  end;

begin
  Result := 0.5;
  S := StripSpace(Branch);
  if (S = '/') then
  begin
    Result := -0.5;
    Exit;
  end;
  { a predicate pattern (XSLT 3.0, 6.6): "." -1, with predicates +1 }
  if S = '.' then
  begin
    Result := -1;
    Exit;
  end;
  if Copy(S, 1, 2) = '.[' then
  begin
    Result := 1;
    Exit;
  end;
  { several steps or a predicate }
  if (Pos8('/', S) > 0) or (Pos8('[', S) > 0) then
    Exit;
  if (Copy(S, 1, 14) = 'document-node(') and (Length(S) > 15) then
  begin
    Result := DefaultPriority(Copy(S, 15, Length(S) - 15));
    Exit;
  end;
  if Copy(S, 1, 7) = 'child::' then
    Delete(S, 1, 7)
  else if Copy(S, 1, 11) = 'attribute::' then
    S := '@' + Copy(S, 12, Length(S) - 11);
  Test := S;
  if Copy(Test, 1, 1) = '@' then
    Delete(Test, 1, 1);
  Test := Trim8(Test);
  if IsQName(Test) or (Copy(Test, 1, 23) = 'processing-instruction(') and (Length(Test) > 24) and
    (Test[Length(Test)] = ')') then
  begin
    Result := 0;
    Exit;
  end;
  if (Test = '*') or (Test = 'node()') or (Test = 'text()') or (Test = 'comment()') or
    (Test = 'processing-instruction()') or (Test = 'document-node()') or (Test = 'element()') or
    (Test = 'attribute()') or (Test = 'element(*)') or (Test = 'attribute(*)') then
  begin
    Result := -0.5;
    Exit;
  end;
  I := Pos8(':', Test);
  if (I > 0) and (((Copy(Test, I + 1, MaxInt) = '*') and IsNCName(Copy(Test, 1, I - 1))) or
    ((Copy(Test, 1, I - 1) = '*') and IsNCName(Copy(Test, I + 1, MaxInt)))) then
  begin
    Result := -0.25;
    Exit;
  end;
  if (Copy(Test, 1, 8) = 'element(') or (Copy(Test, 1, 10) = 'attribute(') then
  begin
    if Pos8(',', Test) > 0 then
    begin
      if Pos8('(*', Test) > 0 then
        Result := 0
      else
        Result := 0.25;
    end
    else
      Result := 0;
  end;
end;

{ The branches of a union pattern (top-level "|"). }
function SplitPattern(const S: TLandrixXmlUtf8): TLandrixXmlUtf8Array;
var
  I, Start, Depth, Comment: Integer;
  Quote: AnsiChar;
begin
  Result := nil;
  Depth := 0;
  Comment := 0;
  Quote := #0;
  Start := 1;
  for I := 1 to Length(S) do
  begin
    if Quote <> #0 then
    begin
      if S[I] = Quote then
        Quote := #0;
      Continue;
    end;
    { XPath comments (nested too): no strings, brackets or separators in
      them }
    if (S[I] = '(') and (I < Length(S)) and (S[I + 1] = ':') then
    begin
      Inc(Comment);
      Continue;
    end;
    if Comment > 0 then
    begin
      if (S[I] = ')') and (S[I - 1] = ':') then
        Dec(Comment);
      Continue;
    end;
    case S[I] of
      '''', '"': Quote := S[I];
      '(', '[': Inc(Depth);
      ')', ']': Dec(Depth);
      '|':
        if Depth = 0 then
        begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := Trim8(Copy(S, Start, I - Start));
          Start := I + 1;
        end;
    end;
  end;
  SetLength(Result, Length(Result) + 1);
  Result[High(Result)] := Trim8(Copy(S, Start, Length(S) - Start + 1));
end;

function CompareRules(Item1, Item2: Pointer): Integer;
var
  A, B: TXsltRule;
begin
  A := TXsltRule(Item1);
  B := TXsltRule(Item2);
  { the rule tried first comes first: precedence, priority, the later one }
  if A.Precedence <> B.Precedence then
    Result := B.Precedence - A.Precedence
  else if A.Priority > B.Priority then
    Result := -1
  else if A.Priority < B.Priority then
    Result := 1
  else
    Result := B.Order - A.Order;
end;

procedure AddRuleToMode(Mode: TXsltMode; R: TXsltRule);
var
  Root, Last, I: Integer;
  Key: string;
  L: TList;
  N: TLandrixXmlXPathAstNode;
begin
  Key := '';
  Root := R.Pattern.Root;
  N := R.Pattern.Nodes[Root];
  if (N.Kind = xakPath) and (Length(N.Children) > 0) then
  begin
    Last := N.Children[High(N.Children)];
    N := R.Pattern.Nodes[Last];
    if (N.Kind = xakStep) and (N.NodeTest = xntName) then
    begin
      if N.Axis = xaxChild then
        Key := 'e' + LandrixXmlUtf8ToKey(XsltClarkOf(N.NamespaceUri, N.LocalName))
      else if N.Axis = xaxAttribute then
        Key := 'a' + LandrixXmlUtf8ToKey(XsltClarkOf(N.NamespaceUri, N.LocalName));
    end;
  end;
  if Key = '' then
  begin
    Mode.Others.Add(R);
    Exit;
  end;
  if Mode.Named.Find(Key, I) then
    L := TList(Mode.Named.Objects[I])
  else
  begin
    L := TList.Create;
    Mode.Named.AddObject(Key, L);
  end;
  L.Add(R);
end;

{ whether Text calls the function Name without a prefix or with the
  prefix fn, outside string literals and XPath comments (the prefix is
  not resolved: fn is taken as the function namespace) }
function CallsFunction(const Text, Name: TLandrixXmlUtf8): Boolean;
var
  I, J, K, Depth: Integer;
  Quote: AnsiChar;
  Same: Boolean;
begin
  Result := False;
  Quote := #0;
  Depth := 0;
  I := 1;
  while I <= Length(Text) do
  begin
    if Quote <> #0 then
    begin
      if Text[I] = Quote then
        Quote := #0;
    end
    else if (Text[I] = '(') and (I < Length(Text)) and (Text[I + 1] = ':') then
    begin
      Inc(Depth);
      Inc(I);
    end
    else if (Depth > 0) and (Text[I] = ':') and (I < Length(Text)) and (Text[I + 1] = ')') then
    begin
      Dec(Depth);
      Inc(I);
    end
    else if Depth > 0 then
      { inside a comment }
    else if (Text[I] = '''') or (Text[I] = '"') then
      Quote := Text[I]
    else if I + Length(Name) - 1 <= Length(Text) then
    begin
      Same := True;
      for K := 1 to Length(Name) do
        if Text[I + K - 1] <> Name[K] then
        begin
          Same := False;
          Break;
        end;
      { not the end of a longer name, and no prefix but fn }
      if Same and (I > 1) and (Text[I - 1] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', #128..#255]) then
        Same := False;
      if Same and (I > 1) and (Text[I - 1] = ':') and
        not ((I >= 4) and (Copy(Text, I - 3, 2) = 'fn') and ((I = 4) or not (Text[I - 4] in ['A'..'Z',
        'a'..'z', '0'..'9', '_', '-', '.', #128..#255]))) then
        Same := False;
      if Same then
      begin
        J := I + Length(Name);
        while (J <= Length(Text)) and (Text[J] in [#9, #10, #13, ' ']) do
          Inc(J);
        if (J <= Length(Text)) and (Text[J] = '(') then
        begin
          Result := True;
          Exit;
        end;
      end;
    end;
    Inc(I);
  end;
end;

{ whether S starts with "." and then "/" (white space between) }
function DotSlash(const S: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (S = '') or (S[1] <> '.') then
    Exit;
  I := 2;
  while (I <= Length(S)) and (S[I] in [#9, #10, #13, ' ']) do
    Inc(I);
  Result := (I <= Length(S)) and (S[I] = '/');
end;

{ Whether the node Index of a compiled pattern branch is a pattern as
  Saxon accepts it (the rules of XSLT 3.0, also for XSLT 2.0): steps on
  the child, attribute, self, descendant and descendant-or-self axes,
  ".", parenthesized patterns and their unions, and at the very start
  (First) a variable or a call of id, key, doc or root; predicates
  anywhere. A number, a string, another function or the parent axis
  as a step is XTSE0340 (error-0340b, "name/1223"). }
function TCompiler.IsPatternNode(X: TLandrixXmlXPathExpression; Index: Integer; First: Boolean): Boolean;
var
  N: TLandrixXmlXPathAstNode;
  J, K: Integer;
  Name: TLandrixXmlUtf8;
begin
  N := X.Nodes[Index];
  case N.Kind of
    xakRoot:
      Result := First;
    xakContextItem:
      { "." at the start only as the whole pattern (".[1]" too; not
        "./b" or "a | .") }
      Result := not First or FDotPattern;
    xakStep:
      Result := N.Axis in [xaxChild, xaxAttribute, xaxSelf, xaxDescendant, xaxDescendantOrSelf];
    xakPath:
      begin
        { the "//" PatternBranch puts before a relative branch (at its
          first byte, also as the first operand of intersect or except):
          the node after it stands at the start }
        if FRelativeBranch and N.RootStart and (N.Position = 1) then
          K := 1
        else if N.RootStart then
        begin
          { "/" only at the start ("a/(/b)" is no pattern) }
          K := -1;
          if not First then
          begin
            Result := False;
            Exit;
          end;
        end
        else
          K := 0;
        Result := True;
        for J := 0 to Integer(Length(N.Children)) - 1 do
          if not IsPatternNode(X, N.Children[J], First and (J = K)) then
            Result := False;
      end;
    xakFilter:
      Result := IsPatternNode(X, N.Children[0], First);
    xakUnion, xakIntersectExcept:
      begin
        Result := True;
        for J := 0 to Integer(Length(N.Children)) - 1 do
          if not IsPatternNode(X, N.Children[J], First) then
            Result := False;
      end;
    xakVariable:
      Result := First;
    xakFunction:
      begin
        Result := False;
        if not First then
          Exit;
        { the arguments: literals and variables ("id(@id)" is no pattern) }
        for J := 0 to Integer(Length(N.Children)) - 1 do
          if not (X.Nodes[N.Children[J]].Kind in [xakString, xakInteger, xakDecimal, xakDouble, xakVariable]) then
            Exit;
        if N.Op >= 0 then
          Result := (N.Op = Ord(xfnId)) or (N.Op = Ord(xfnRoot)) or (N.Op = Ord(xfnDoc))
        else
        begin
          { the functions of the stylesheet's context, in the order
            NewContext declares them }
          K := -1 - N.Op;
          if (K < Integer(Length(FC.FunctionNames))) and (FC.FunctionUris[K] = LandrixXmlXPathFunctionNamespace) then
          begin
            Name := FC.FunctionNames[K];
            Result := (Name = 'key') or (Name = 'doc') or (Name = 'id') or (Name = 'root');
          end;
        end;
      end;
  else
    Result := False;
  end;
end;

{ A branch of a pattern as the expression MatchesPattern takes: "//"
  before a relative path (Relative), rooted ones as they are,
  document-node(...) as the root tested. }
function TCompiler.PatternBranch(M: TModule; E: Integer; const Branch: TLandrixXmlUtf8; Scope: TScope;
  out Relative: Boolean): TLandrixXmlXPathExpression;
var
  B, Text: TLandrixXmlUtf8;
begin
  { no current group in a pattern (XSLT 2.0 14) }
  if CallsFunction(Branch, 'current-group') then
    Fail(M, E, 'XTSE1060', 'current-group() in a pattern');
  if CallsFunction(Branch, 'current-grouping-key') then
    Fail(M, E, 'XTSE1070', 'current-grouping-key() in a pattern');
  B := Branch;
  if StripSpace(B) = 'document-node()' then
    B := '/'
  else if Copy(StripSpace(B), 1, 14) = 'document-node(' then
    B := '/self::' + B;
  if (B[1] = '/') or (Copy(B, 1, 3) = 'id(') or (Copy(B, 1, 4) = 'key(') or (Copy(B, 1, 4) = 'doc(') then
  begin
    Text := B;
    Relative := False;
  end
  else
  begin
    Text := '//' + B;
    Relative := True;
  end;
  Result := nil;
  try
    Result := Compile(M, E, Text, Scope);
  except
    on X: ELandrixXmlXsltError do
      if X.XPathCode = 'XPST0003' then
        Fail(M, E, 'XTSE0340', 'not a pattern: "' + LandrixXmlUtf8ToString(Branch) + '"')
      else
        raise;
  end;
  FRelativeBranch := Relative;
  { "." at the start: the pattern has this branch alone, and it is not
    "./" or ".//" (Saxon accepts "(.)/b"; the parentheses are gone from
    the tree, so "(.)[1]" and "(. | a)" pass too) }
  FDotPattern := FSingleBranch and not DotSlash(Branch);
  { (the expression belongs to FC.Expressions) }
  if not IsPatternNode(Result, Result.Root, True) then
    Fail(M, E, 'XTSE0340', 'not a pattern: "' + LandrixXmlUtf8ToString(Branch) + '"');
end;

{ xsl:number (XSLT 2.0 12): value or the place of the selected node
  (level, count, from), the format, lang, ordinal, letter-value and the
  grouping as templates. }
procedure TCompiler.CompileNumber(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
var
  V: TLandrixXmlUtf8;
  Branches: TLandrixXmlUtf8Array;
  I: Integer;
begin
  Branches := nil;
  for I := E + 1 to E + M.Tree.AttributeCount[E] do
    if M.Tree.NamespaceUriUtf8(I) = '' then
    begin
      V := M.Tree.LocalNameUtf8(I);
      if (V <> 'value') and (V <> 'select') and (V <> 'level') and (V <> 'count') and (V <> 'from') and
        (V <> 'format') and (V <> 'lang') and (V <> 'letter-value') and (V <> 'ordinal') and
        (V <> 'grouping-separator') and (V <> 'grouping-size') and (V <> 'start-at') and (V <> 'version') and
        (V <> 'xpath-default-namespace') and (V <> 'exclude-result-prefixes') and
        (V <> 'extension-element-prefixes') and (V <> 'use-when') and (V <> 'expand-text') and
        (V <> 'default-collation') and (V <> 'default-validation') and (V <> 'default-mode') and
        (V <> 'input-type-annotations') and not Forwards(M, E) then
        Fail(M, E, 'XTSE0090', 'xsl:number has no attribute ' + LandrixXmlUtf8ToString(V));
      if V = 'start-at' then
        Unsupported(M, E, 'xsl:number start-at (XSLT 3.0)');
    end;
  I := M.Tree.FirstChild(E);
  while I >= 0 do
  begin
    if (M.Tree.Kind[I] = xnkElement) or (M.Tree.Kind[I] = xnkText) and (Trim8(M.Tree.ValueUtf8(I)) <> '') then
      Fail(M, E, 'XTSE0260', 'xsl:number must be empty');
    I := M.Tree.NextSibling[I];
  end;
  Instr.NumberValue := CompileAttr(M, E, 'value', Scope);
  Instr.Select := CompileAttr(M, E, 'select', Scope);
  if (Instr.NumberValue <> nil) and ((Instr.Select <> nil) or Attr(M, E, 'level', V) or Attr(M, E, 'count', V) or
    Attr(M, E, 'from', V)) then
    Fail(M, E, 'XTSE0975', 'xsl:number has value and select, level, count or from');
  Instr.NumberLevel := 0;
  if Attr(M, E, 'level', V) then
  begin
    V := Trim8(V);
    if V = 'multiple' then
      Instr.NumberLevel := 1
    else if V = 'any' then
      Instr.NumberLevel := 2
    else if V <> 'single' then
      Fail(M, E, 'XTSE0020', 'level must be single, multiple or any');
  end;
  if Attr(M, E, 'count', V) then
  begin
    Branches := SplitPattern(V);
    FSingleBranch := Length(Branches) = 1;
    SetLength(Instr.CountPatterns, Length(Branches));
    SetLength(Instr.CountRelative, Length(Branches));
    for I := 0 to Integer(Length(Branches)) - 1 do
    begin
      if Branches[I] = '' then
        Fail(M, E, 'XTSE0340', 'an empty pattern');
      Instr.CountPatterns[I] := PatternBranch(M, E, Branches[I], Scope, Instr.CountRelative[I]);
    end;
  end;
  if Attr(M, E, 'from', V) then
  begin
    Branches := SplitPattern(V);
    FSingleBranch := Length(Branches) = 1;
    SetLength(Instr.FromPatterns, Length(Branches));
    SetLength(Instr.FromRelative, Length(Branches));
    for I := 0 to Integer(Length(Branches)) - 1 do
    begin
      if Branches[I] = '' then
        Fail(M, E, 'XTSE0340', 'an empty pattern');
      Instr.FromPatterns[I] := PatternBranch(M, E, Branches[I], Scope, Instr.FromRelative[I]);
    end;
  end;
  if not Attr(M, E, 'format', V) then
    V := '1';
  Instr.FormatAvt := CompileAvt(M, E, V, Scope);
  if Attr(M, E, 'lang', V) and (V <> '') then
    Instr.NumberLang := CompileAvt(M, E, V, Scope);
  if Attr(M, E, 'ordinal', V) then
    Instr.NumberOrdinal := CompileAvt(M, E, V, Scope);
  { Saxon trims a literal letter-value, not the value of an expression }
  if Attr(M, E, 'letter-value', V) then
    Instr.LetterValue := CompileAvt(M, E, Trim8(V), Scope);
  if Attr(M, E, 'grouping-separator', V) then
    Instr.GroupingSeparator := CompileAvt(M, E, V, Scope);
  if Attr(M, E, 'grouping-size', V) then
    Instr.GroupingSize := CompileAvt(M, E, V, Scope);
end;

{ xsl:for-each-group: the population, one of group-by, group-adjacent,
  group-starting-with and group-ending-with (XTSE1080), the body. Only
  the Unicode codepoint collation. }
procedure TCompiler.CompileGroup(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
var
  V, Pattern: TLandrixXmlUtf8;
  Branches: TLandrixXmlUtf8Array;
  I, Count, C: Integer;
begin
  Branches := nil;
  Instr.Select := Compile(M, E, ReqAttr(M, E, 'select'), Scope);
  Count := 0;
  if Attr(M, E, 'group-by', V) then
  begin
    Instr.GroupKind := 0;
    Instr.Test := Compile(M, E, V, Scope);
    Inc(Count);
  end;
  if Attr(M, E, 'group-adjacent', V) then
  begin
    Instr.GroupKind := 1;
    Instr.Test := Compile(M, E, V, Scope);
    Inc(Count);
  end;
  if Attr(M, E, 'group-starting-with', V) then
  begin
    Instr.GroupKind := 2;
    Pattern := V;
    Inc(Count);
  end;
  if Attr(M, E, 'group-ending-with', V) then
  begin
    Instr.GroupKind := 3;
    Pattern := V;
    Inc(Count);
  end;
  if Count <> 1 then
    Fail(M, E, 'XTSE1080', 'xsl:for-each-group needs exactly one of group-by, group-adjacent, ' +
      'group-starting-with and group-ending-with');
  if (Instr.GroupKind <= 1) and Attr(M, E, 'collation', V) then
  begin
    Instr.CollationAvt := CompileAvt(M, E, V, Scope);
    if AvtLiteral(Instr.CollationAvt, V) then
      CheckCollation(Self, M, E, Trim8(V), 'XTDE1110');
  end;
  if Instr.GroupKind >= 2 then
  begin
    if Attr(M, E, 'collation', V) then
      Fail(M, E, 'XTSE1090', 'collation only with group-by or group-adjacent');
    Branches := SplitPattern(Pattern);
    FSingleBranch := Length(Branches) = 1;
    SetLength(Instr.CountPatterns, Length(Branches));
    SetLength(Instr.CountRelative, Length(Branches));
    for I := 0 to Integer(Length(Branches)) - 1 do
    begin
      if Branches[I] = '' then
        Fail(M, E, 'XTSE0340', 'an empty pattern');
      Instr.CountPatterns[I] := PatternBranch(M, E, Branches[I], Scope, Instr.CountRelative[I]);
    end;
  end;
  C := CompileSorts(M, E, Scope, Instr);
  if C >= 0 then
    CompileBody(M, E, Scope, Instr.Body, C);
end;

{ an NCName (XML 1.0 fifth edition name characters, no colon) }
function IsNCName8(const S: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (S = '') or (LandrixXmlCheckName(PAnsiChar(S), Length(S)) >= 0) then
    Exit;
  for I := 1 to Length(S) do
    if S[I] = ':' then
      Exit;
  Result := True;
end;

function XsltFormatClark(const Name: TLandrixXmlUtf8; const Prefixes, Uris: TLandrixXmlUtf8Array): TLandrixXmlUtf8;
var
  I, P: Integer;
  Prefix, Local: TLandrixXmlUtf8;
begin
  Result := '';
  if Copy(Name, 1, 2) = 'Q{' then
  begin
    P := Pos8('}', Name);
    if (P > 0) and IsNCName8(Copy(Name, P + 1, MaxInt)) then
      Result := XsltClarkOf(Copy(Name, 3, P - 3), Copy(Name, P + 1, MaxInt));
    Exit;
  end;
  P := Pos8(':', Name);
  if P = 0 then
  begin
    if IsNCName8(Name) then
      Result := Name;
    Exit;
  end;
  Prefix := Copy(Name, 1, P - 1);
  Local := Copy(Name, P + 1, MaxInt);
  if not IsNCName8(Prefix) or not IsNCName8(Local) then
    Exit;
  for I := 0 to Integer(Length(Prefixes)) - 1 do
    if Prefixes[I] = Prefix then
      Result := XsltClarkOf(Uris[I], Local);
end;

function XsltCDataNames(const Value: TLandrixXmlUtf8; const Prefixes, Uris: TLandrixXmlUtf8Array;
  out Names, Bad: TLandrixXmlUtf8): Boolean;
var
  I, J, Start: Integer;
  T, C, Default: TLandrixXmlUtf8;
begin
  Result := False;
  Names := '';
  Bad := '';
  Default := '';
  for J := 0 to Integer(Length(Prefixes)) - 1 do
    if Prefixes[J] = '' then
      Default := Uris[J];
  I := 1;
  while I <= Length(Value) do
  begin
    while (I <= Length(Value)) and (Value[I] in [#9, #10, #13, ' ']) do
      Inc(I);
    Start := I;
    while (I <= Length(Value)) and not (Value[I] in [#9, #10, #13, ' ']) do
      Inc(I);
    if I = Start then
      Continue;
    T := Copy(Value, Start, I - Start);
    if (Copy(T, 1, 2) <> 'Q{') and (Pos8(':', T) = 0) then
    begin
      C := '';
      if IsNCName8(T) then
        C := XsltClarkOf(Default, T);
    end
    else
      C := XsltFormatClark(T, Prefixes, Uris);
    if C = '' then
    begin
      Bad := T;
      Exit;
    end;
    if Names <> '' then
      Names := Names + ' ';
    Names := Names + C;
  end;
  Result := True;
end;

procedure XsltNameArgument(Evaluator: TLandrixXmlXPathEvaluator; const Arg: TLandrixXmlXPathSequence;
  const Code, FunctionName: string; const DefaultUri: TLandrixXmlUtf8; out Uri, Local: TLandrixXmlUtf8);
var
  S, Prefix: TLandrixXmlUtf8;
  A, B, I: Integer;
begin
  S := Evaluator.ItemString(Evaluator.ConvertSequence(Arg, LandrixXmlXPathParseSequenceType('xs:string', nil),
    FunctionName).Items[0]);
  A := 1;
  B := Length(S);
  while (A <= B) and (S[A] in [#9, #10, #13, ' ']) do
    Inc(A);
  while (B >= A) and (S[B] in [#9, #10, #13, ' ']) do
    Dec(B);
  S := Copy(S, A, B - A + 1);
  I := Pos8(':', S);
  Uri := DefaultUri;
  Local := S;
  Prefix := '';
  if I > 0 then
  begin
    Prefix := Copy(S, 1, I - 1);
    Local := Copy(S, I + 1, Length(S) - I);
  end;
  if (I = 0) and (DefaultUri = '#') and ((Evaluator.CallerExpression = nil) or
    not Evaluator.CallerExpression.LookupNamespace('#ns:', Uri)) then
    Uri := '';
  if (I > 0) and (Prefix = 'xml') then
    Uri := LandrixXmlNamespaceXml;
  if not IsNCName8(Local) or (I > 0) and (Prefix <> 'xml') and (not IsNCName8(Prefix) or
    (Evaluator.CallerExpression = nil) or not Evaluator.CallerExpression.LookupNamespace('#ns:' + Prefix, Uri) or
    (Uri = '')) then
    raise ELandrixXmlXPathError.CreateXPath(Code, FunctionName + ': ' + LandrixXmlUtf8ToString(S) +
      ' is no QName with a bound prefix');
end;

function XsltSystemProperty(const Uri, Local: TLandrixXmlUtf8): TLandrixXmlUtf8;
begin
  Result := '';
  if Uri <> XsltNamespace then
    Exit;
  if Local = 'version' then
    Result := '2.0'
  else if Local = 'vendor' then
    Result := 'Landrix Software'
  else if Local = 'vendor-url' then
    Result := 'https://github.com/landrix/LandrixXML-for-Pascal'
  else if Local = 'product-name' then
    Result := 'LandrixXML'
  else if Local = 'product-version' then
    Result := LandrixXmlVersion
  else if Local = 'is-schema-aware' then
    Result := 'no'
  else if (Local = 'supports-serialization') or (Local = 'supports-backwards-compatibility') then
    Result := 'yes';
end;

function XsltArityArgument(Evaluator: TLandrixXmlXPathEvaluator; const Arg: TLandrixXmlXPathSequence): Integer;
var
  Count: TLandrixXmlUtf8;
begin
  Result := -1;
  Count := Evaluator.ItemString(Evaluator.ConvertSequence(Arg, LandrixXmlXPathParseSequenceType('xs:integer', nil),
    'function-available()').Items[0]);
  if (Count = '') or (Count[1] <> '-') then
    if Length(Count) > 9 then
      Result := MaxInt
    else
      Result := StrToInt(LandrixXmlUtf8ToString(Count));
end;

function XsltFunctionAvailable(Evaluator: TLandrixXmlXPathEvaluator; FC: TXsltCompiled;
  const Uri, Local: TLandrixXmlUtf8; Arity: Integer): Boolean;
const
  { the XSLT functions of the fixed and per-module part of the table, for
    use-when (name and arity) }
  Fixed: array[0..28] of string = ('current/0', 'format-dateTime/2', 'format-dateTime/5', 'format-date/2',
    'format-date/5', 'format-time/2', 'format-time/5', 'current-group/0', 'current-grouping-key/0',
    'generate-id/0', 'generate-id/1', 'key/2', 'key/3', 'format-number/2', 'format-number/3',
    'system-property/1', 'function-available/1', 'function-available/2', 'element-available/1',
    'regex-group/1', 'doc/1', 'doc-available/1', 'document/1', 'static-base-uri/0', 'resolve-uri/1',
    'unparsed-text/1', 'unparsed-text/2', 'unparsed-text-available/1', 'unparsed-text-available/2');
var
  I, P: Integer;
  Name: string;
begin
  Result := (Evaluator.CallerExpression <> nil) and
    LandrixXmlXPathBuiltinExists(Uri, Local, Arity, Evaluator.CallerExpression.Profile);
  if Result then
    Exit;
  if Length(FC.FunctionNames) = 0 then
  begin
    if Uri <> LandrixXmlXPathFunctionNamespace then
      Exit;
    for I := Low(Fixed) to High(Fixed) do
    begin
      P := Pos('/', Fixed[I]);
      Name := Copy(Fixed[I], 1, P - 1);
      if (LandrixXmlStringToUtf8(Name) = Local) and
        ((Arity < 0) or (StrToInt(Copy(Fixed[I], P + 1, MaxInt)) = Arity)) then
      begin
        Result := True;
        Exit;
      end;
    end;
    Exit;
  end;
  for I := 0 to Integer(Length(FC.FunctionNames)) - 1 do
    if (FC.FunctionNames[I] = Local) and (FC.FunctionUris[I] = Uri) and
      ((Arity < 0) or (FC.FunctionArities[I] = Arity)) and (I <> XfnGlobal) and
      not ((Local = 'document') and (FC.FunctionArities[I] = 2) and (Uri = LandrixXmlXPathFunctionNamespace)) then
    begin
      Result := True;
      Exit;
    end;
end;

{ xsl:strip-space or xsl:preserve-space: its elements attribute, a list
  of name tests ("*", "prefix:*", "*:name" or a QName; the EQName of
  XSLT 3.0 is not supported) }
procedure TCompiler.CompileSpace(D: TDecl; Strip: Boolean);
var
  M: TModule;
  E, I, Start, N, P: Integer;
  List, Token, Prefix, Uri, Local: TLandrixXmlUtf8;
  Kind: Integer;
begin
  M := D.Module;
  E := D.Element;
  List := ReqAttr(M, E, 'elements');
  I := 1;
  while I <= Length(List) do
  begin
    while (I <= Length(List)) and (List[I] in [#9, #10, #13, ' ']) do
      Inc(I);
    Start := I;
    while (I <= Length(List)) and not (List[I] in [#9, #10, #13, ' ']) do
      Inc(I);
    if I = Start then
      Break;
    Token := Copy(List, Start, I - Start);
    Uri := '';
    Local := '';
    if (Length(Token) >= 2) and (Token[1] = 'Q') and (Token[2] = '{') then
      Unsupported(M, E, 'a name test Q{uri}name (XSLT 3.0)');
    if Token = '*' then
      Kind := 2
    else if (Length(Token) > 2) and (Token[1] = '*') and (Token[2] = ':') then
    begin
      Kind := 3;
      Local := Copy(Token, 3, MaxInt);
      Prefix := '';
      if not IsNCName8(Local) then
        Fail(M, E, 'XTSE0020', 'not a name test: "' + LandrixXmlUtf8ToString(Token) + '"');
    end
    else
    begin
      P := Pos8(':', Token);
      { an empty prefix is one that is not declared (as in Saxon) }
      if P = 1 then
        Fail(M, E, 'XTSE0280', 'the empty prefix in "' + LandrixXmlUtf8ToString(Token) + '" is not declared');
      if (P > 1) and (Copy(Token, P + 1, MaxInt) = '*') then
      begin
        Kind := 1;
        Prefix := Copy(Token, 1, P - 1);
      end
      else
      begin
        Kind := 0;
        if P > 0 then
        begin
          Prefix := Copy(Token, 1, P - 1);
          Local := Copy(Token, P + 1, MaxInt);
        end
        else
        begin
          Prefix := '';
          Local := Token;
        end;
        if not IsNCName8(Local) then
          Fail(M, E, 'XTSE0020', 'not a name test: "' + LandrixXmlUtf8ToString(Token) + '"');
      end;
      if Prefix <> '' then
      begin
        if not IsNCName8(Prefix) then
          Fail(M, E, 'XTSE0020', 'not a name test: "' + LandrixXmlUtf8ToString(Token) + '"');
        if Prefix = 'xml' then
          Uri := 'http://www.w3.org/XML/1998/namespace'
        else if not M.Tree.LookupNamespace(E, Prefix, Uri) or (Uri = '') then
          Fail(M, E, 'XTSE0280', 'the prefix ' + LandrixXmlUtf8ToString(Prefix) + ' is not declared');
      end
      else if Kind = 0 then
        { an unprefixed name: the default element namespace of XPath }
        Uri := XPathDefaultNamespace(M, E);
    end;
    N := Integer(Length(FC.SpaceKinds));
    SetLength(FC.SpaceKinds, N + 1);
    SetLength(FC.SpaceUris, N + 1);
    SetLength(FC.SpaceLocals, N + 1);
    SetLength(FC.SpaceStrip, N + 1);
    SetLength(FC.SpacePrecedences, N + 1);
    SetLength(FC.SpaceOrders, N + 1);
    FC.SpaceKinds[N] := Kind;
    FC.SpaceUris[N] := Uri;
    FC.SpaceLocals[N] := Local;
    FC.SpaceStrip[N] := Strip;
    FC.SpacePrecedences[N] := D.Precedence;
    FC.SpaceOrders[N] := D.Order;
    if Strip then
      FC.HasStrip := True;
  end;
end;

function IsQName8(const S: TLandrixXmlUtf8): Boolean; forward;

{ xsl:key: the declarations of one name are combined (all precedences);
  key() resolves a prefix of the name with the namespaces of the calling
  expression. }
procedure TCompiler.CompileKey(D: TDecl);
var
  M: TModule;
  E, I: Integer;
  Name, V: TLandrixXmlUtf8;
  Branches: TLandrixXmlUtf8Array;
  K: TXsltKey;
  Decl: TXsltKeyDecl;
  HasUse, HasBody: Boolean;
  Scope: TScope;
begin
  M := D.Module;
  E := D.Element;
  Branches := nil;
  V := Trim8(ReqAttr(M, E, 'name'));
  if not IsQName8(V) then
    Fail(M, E, 'XTSE0020', 'the name of xsl:key is not a QName: "' + LandrixXmlUtf8ToString(V) + '"');
  Name := DeclName(M, E, V);
  if Attr(M, E, 'collation', V) then
    CheckCollation(Self, M, E, Trim8(V), 'XTSE1210');
  HasUse := Attr(M, E, 'use', V);
  I := M.Tree.FirstChild(E);
  HasBody := False;
  while I >= 0 do
  begin
    if (M.Tree.Kind[I] = xnkElement) or (M.Tree.Kind[I] = xnkText) and
      ((Trim8(M.Tree.ValueUtf8(I)) <> '') or PreservesSpace(M.Tree, I)) then
      HasBody := True;
    I := M.Tree.NextSibling[I];
  end;
  if HasUse and HasBody then
    Fail(M, E, 'XTSE1205', 'xsl:key has use and content');
  if not HasUse and not HasBody then
    Fail(M, E, 'XTSE1205', 'xsl:key needs use or content');
  I := FC.Keys.IndexOf(LandrixXmlUtf8ToKey(Name));
  if I >= 0 then
    K := TXsltKey(FC.Keys.Objects[I])
  else
  begin
    K := TXsltKey.Create;
    K.Name := Name;
    K.Index := Integer(FC.Keys.Count);
    FC.Keys.AddObject(LandrixXmlUtf8ToKey(Name), K);
  end;
  Decl := TXsltKeyDecl.Create;
  K.Decls.Add(Decl);
  Decl.Backwards := Backwards(M, E);
  if HasUse then
    Decl.Use := Compile(M, E, V, nil)
  else
  begin
    { the sequence constructor with the globals in scope }
    Scope := TScope.Create;
    try
      Scope.NextSlot := FC.GlobalCount;
      Scope.MaxSlot := FC.GlobalCount;
      CompileBody(M, E, Scope, Decl.Body, -1);
      Decl.FrameSize := Scope.MaxSlot;
    finally
      Scope.Free;
    end;
  end;
  Branches := SplitPattern(ReqAttr(M, E, 'match'));
  FSingleBranch := Length(Branches) = 1;
  SetLength(Decl.Patterns, Length(Branches));
  SetLength(Decl.Relative, Length(Branches));
  for I := 0 to Integer(Length(Branches)) - 1 do
  begin
    if Branches[I] = '' then
      Fail(M, E, 'XTSE0340', 'an empty pattern');
    Decl.Patterns[I] := PatternBranch(M, E, Branches[I], nil, Decl.Relative[I]);
  end;
end;

{ xsl:decimal-format: a name without prefix (format-number() gets it as a
  string and resolves no prefixes), the characters one each (XTSE0020) }

procedure TCompiler.CompileDecimalFormat(D: TDecl);
var
  M: TModule;
  E, I, J, K: Integer;
  Name, L, V: TLandrixXmlUtf8;
  F: TXPathDecimalFormat;

  function CharCount(const S: TLandrixXmlUtf8): Integer;
  var
    J: Integer;
  begin
    Result := 0;
    for J := 1 to Length(S) do
      if Ord(S[J]) and $C0 <> $80 then
        Inc(Result);
  end;

begin
  M := D.Module;
  E := D.Element;
  Name := '';
  if Attr(M, E, 'name', V) then
  begin
    V := Trim8(V);
    if Pos8(':', V) > 0 then
      Unsupported(M, E, 'a decimal format name with a prefix');
    if not IsNCName8(V) then
      Fail(M, E, 'XTSE0020', 'not a decimal format name: "' + LandrixXmlUtf8ToString(V) + '"');
    Name := V;
  end;
  K := FC.DecimalFormats.IndexOf(LandrixXmlUtf8ToKey(Name));
  if K >= 0 then
    F := TXPathDecimalFormat(FC.DecimalFormats.Objects[K])
  else
  begin
    F := TXPathDecimalFormat.Create;
    FC.DecimalFormats.AddObject(LandrixXmlUtf8ToKey(Name), F);
  end;
  for I := E + 1 to E + M.Tree.AttributeCount[E] do
  begin
    if M.Tree.NamespaceUriUtf8(I) <> '' then
      Continue;
    L := M.Tree.LocalNameUtf8(I);
    V := M.Tree.ValueUtf8(I);
    if (L = 'name') or (L = 'infinity') or (L = 'NaN') then
      { strings }
    else if (L = 'xpath-default-namespace') or (L = 'exclude-result-prefixes') or
      (L = 'extension-element-prefixes') or (L = 'use-when') or (L = 'expand-text') or (L = 'version') or
      (L = 'default-mode') or (L = 'default-collation') then
      { standard attributes (CheckStandard): no property }
      Continue
    else if (L = 'decimal-separator') or (L = 'grouping-separator') or (L = 'minus-sign') or (L = 'percent') or
      (L = 'per-mille') or (L = 'zero-digit') or (L = 'digit') or (L = 'pattern-separator') then
    begin
      if CharCount(V) <> 1 then
        Fail(M, E, 'XTSE0020', 'xsl:decimal-format ' + LandrixXmlUtf8ToString(L) + ' must be one character');
    end
    else
    begin
      { forwards compatible: an unknown attribute is ignored }
      if not Forwards(M, E) then
        Fail(M, E, 'XTSE0090', 'xsl:decimal-format has no attribute ' + LandrixXmlUtf8ToString(L));
      Continue;
    end;
    { a property given twice with the same precedence and different values
      (XTSE1290); a higher precedence wins }
    if L <> 'name' then
    begin
      J := F.PropertyIndex(L);
      if F.Precedences[J] > D.Precedence then
        Continue;
      if (F.Precedences[J] = D.Precedence) and (F.Values[J] <> V) then
        Fail(M, E, 'XTSE1290', 'two values of ' + LandrixXmlUtf8ToString(L) + ' for the decimal format "' +
          LandrixXmlUtf8ToString(Name) + '"');
      F.Precedences[J] := D.Precedence;
      F.Values[J] := V;
    end;
    if L = 'decimal-separator' then
      F.DecimalSeparator := V
    else if L = 'grouping-separator' then
      F.GroupingSeparator := V
    else if L = 'infinity' then
      F.Infinity := V
    else if L = 'minus-sign' then
      F.MinusSign := V
    else if L = 'NaN' then
      F.NaN := V
    else if L = 'percent' then
      F.Percent := V
    else if L = 'per-mille' then
      F.PerMille := V
    else if L = 'zero-digit' then
      F.ZeroDigit := V
    else if L = 'digit' then
      F.Digit := V
    else if L = 'pattern-separator' then
      F.PatternSeparator := V;
  end;
  if F.ZeroDigit <> '0' then
  begin
    if (Length(F.ZeroDigit) = 1) or not (F.ZeroDigit[1] in [#$C0..#$FF]) then
      Fail(M, E, 'XTSE1295', 'the zero digit must be a digit of value zero');
    Unsupported(M, E, 'a zero digit other than 0');
  end;
  { the characters that format a number are distinct }
  if (F.DecimalSeparator = F.GroupingSeparator) or (F.DecimalSeparator = F.Percent) or
    (F.DecimalSeparator = F.PerMille) or (F.DecimalSeparator = F.Digit) or
    (F.DecimalSeparator = F.PatternSeparator) or (F.GroupingSeparator = F.Percent) or
    (F.GroupingSeparator = F.PerMille) or (F.GroupingSeparator = F.Digit) or
    (F.GroupingSeparator = F.PatternSeparator) or (F.Percent = F.PerMille) or (F.Percent = F.Digit) or
    (F.Percent = F.PatternSeparator) or (F.PerMille = F.Digit) or (F.PerMille = F.PatternSeparator) or
    (F.Digit = F.PatternSeparator) or
    (Length(F.DecimalSeparator) = 1) and (F.DecimalSeparator[1] in ['0'..'9']) or
    (Length(F.GroupingSeparator) = 1) and (F.GroupingSeparator[1] in ['0'..'9']) or
    (Length(F.Digit) = 1) and (F.Digit[1] in ['0'..'9']) or
    (Length(F.PatternSeparator) = 1) and (F.PatternSeparator[1] in ['0'..'9']) or
    (Length(F.Percent) = 1) and (F.Percent[1] in ['0'..'9']) or
    (Length(F.PerMille) = 1) and (F.PerMille[1] in ['0'..'9']) then
    Fail(M, E, 'XTSE1300', 'the characters of a decimal format must be distinct');
end;

procedure TCompiler.AddRules(D: TDecl; T: TXsltTemplate; const Match: TLandrixXmlUtf8; const Modes: TLandrixXmlUtf8;
  HasModes: Boolean);
var
  Branches: TLandrixXmlUtf8Array;
  ModeNames: TList;
  I, J, Start: Integer;
  R: TXsltRule;
  B, V, W: TLandrixXmlUtf8;
  Prio: Double;
  HasPrio, All: Boolean;
  Count: Integer;
  Mode: TXsltMode;
begin
  HasPrio := not D.Simplified and Attr(D.Module, D.Element, 'priority', V);
  Prio := 0;
  if HasPrio then
  begin
    { the library's parser, not Val (255 characters on FPC, EOverflow on
      x87): the same value on every compiler }
    if not IsDecimal(Trim8(V)) or not LandrixXmlTryParseDouble(Trim8(V), Prio) then
      Fail(D.Module, D.Element, 'XTSE0530', 'the priority "' + LandrixXmlUtf8ToString(V) + '" is not a number');
  end;
  ModeNames := TList.Create;
  try
    All := False;
    Mode := nil;
    Count := 0;
    W := Modes + ' ';
    Start := 1;
    for I := 1 to Length(W) do
      if W[I] in [#9, #10, #13, ' '] then
      begin
        B := Copy(W, Start, I - Start);
        Start := I + 1;
        if B = '' then
          Continue;
        Inc(Count);
        { XTSE0550: #all alone, no mode twice, no other #token }
        if B = '#all' then
          All := True
        { #default: the default mode at the template ([xsl:]default-mode,
          XSLT 3.0); #unnamed (XSLT 3.0) the unnamed mode, in Saxon also
          in 2.0 }
        else if B = '#default' then
          Mode := ModeOf(DefaultModeOf(D.Module, D.Element))
        else if B = '#unnamed' then
          Mode := ModeOf('')
        else if (B[1] = '#') or not IsQName8(B) and (Copy(B, 1, 2) <> 'Q{') then
          Fail(D.Module, D.Element, 'XTSE0550', 'the mode ' + LandrixXmlUtf8ToString(B) + ' is not allowed here')
        else
          Mode := ModeOf(ModeName(D.Module, D.Element, B));
        if B <> '#all' then
        begin
          if ModeNames.IndexOf(Mode) >= 0 then
            Fail(D.Module, D.Element, 'XTSE0550', 'the mode ' + LandrixXmlUtf8ToString(B) + ' is listed twice');
          ModeNames.Add(Mode);
        end;
      end;
    if All and (Count > 1) then
      Fail(D.Module, D.Element, 'XTSE0550', 'mode="#all" cannot be combined with other modes');
    if HasModes and (Count = 0) then
      Fail(D.Module, D.Element, 'XTSE0550', 'an empty mode attribute');
    { the default mode (that of a simplified stylesheet's literal result
      element too, the mode it starts in) }
    if Count = 0 then
      ModeNames.Add(ModeOf(DefaultModeOf(D.Module, D.Element)));
    Branches := SplitPattern(Match);
    FSingleBranch := Length(Branches) = 1;
    for I := 0 to Integer(Length(Branches)) - 1 do
    begin
      B := Branches[I];
      if B = '' then
        Fail(D.Module, D.Element, 'XTSE0340', 'an empty pattern');
      R := TXsltRule.Create;
      FC.Rules.Add(R);
      R.Template := T;
      R.Precedence := D.Precedence;
      R.Order := D.Order;
      R.Explicit := HasPrio;
      if HasPrio then
        R.Priority := Prio
      else
        R.Priority := DefaultPriority(B);
      R.Pattern := PatternBranch(D.Module, D.Element, B, nil, R.Relative);
      if All then
        FAllModeTemplates.Add(R)
      else
        for J := 0 to Integer(ModeNames.Count) - 1 do
          AddRuleToMode(TXsltMode(ModeNames[J]), R);
    end;
  finally
    ModeNames.Free;
  end;
end;

{ The xsl:function declarations: for each name and arity the one with the
  highest import precedence (XTSE0770 for two with the same). Their
  bodies are compiled after the globals and templates (CompileFunction),
  their names are known to every expression before. }
procedure TCompiler.CollectFunctions;
var
  I, K, C, Arity: Integer;
  D: TDecl;
  M: TModule;
  T: TXsltTemplate;
  Name, Uri, Key: TLandrixXmlUtf8;
  Keys: TXsltStringList;
  DupTemplates, DupDecls: TList;
begin
  Keys := TXsltStringList.Create;
  DupTemplates := TList.Create;
  DupDecls := TList.Create;
  try
    Keys.CaseSensitive := True;
    for I := 0 to Integer(FDecls.Count) - 1 do
    begin
      D := TDecl(FDecls[I]);
      M := D.Module;
      if not IsXsl(M, D.Element, 'function') then
        Continue;
      Name := QNameToClark(M, D.Element, Trim8(ReqAttr(M, D.Element, 'name')), False);
      Uri := '';
      if Copy(Name, 1, 1) = '{' then
        Uri := Copy(Name, 2, Pos8('}', Name) - 2);
      if Uri = '' then
        Fail(M, D.Element, 'XTSE0740', 'a stylesheet function needs a name in a namespace');
      if ReservedNamespace(Uri) then
        Fail(M, D.Element, 'XTSE0080', 'a stylesheet function in a reserved namespace');
      Arity := 0;
      C := M.Tree.FirstChild(D.Element);
      while C >= 0 do
      begin
        if IsXsl(M, C, 'param') then
          Inc(Arity);
        C := M.Tree.NextSibling[C];
      end;
      Key := Name + '#' + LandrixXmlStringToUtf8(IntToStr(Arity));
      K := Keys.IndexOf(LandrixXmlUtf8ToKey(Key));
      if K >= 0 then
      begin
        T := TXsltTemplate(Keys.Objects[K]);
        { two with the same precedence: an error unless a higher one
          replaces both (checked at the end) }
        if T.Precedence = D.Precedence then
        begin
          DupTemplates.Add(T);
          DupDecls.Add(D);
          Continue;
        end;
        if T.Precedence > D.Precedence then
          Continue;
        { a higher precedence: this declaration instead }
        K := Integer(FC.UserFunctions.IndexOf(T));
        FFunctionDecls[K] := D;
        T.Precedence := D.Precedence;
        T.Module := M.Uri;
        T.Line := M.LineOf(D.Element);
        T.Column := M.ColumnOf(D.Element);
        Continue;
      end;
      T := TXsltTemplate.Create;
      FC.Templates.Add(T);
      T.Name := Name;
      T.Module := M.Uri;
      T.Line := M.LineOf(D.Element);
      T.Column := M.ColumnOf(D.Element);
      T.Precedence := D.Precedence;
      { the parameters, to count them (CompileFunction compiles them) }
      for C := 1 to Arity do
        T.Params.Add(nil);
      FC.UserFunctions.Add(T);
      FFunctionDecls.Add(D);
      Keys.AddObject(LandrixXmlUtf8ToKey(Key), T);
    end;
    for I := 0 to Integer(DupTemplates.Count) - 1 do
      if TXsltTemplate(DupTemplates[I]).Precedence = TDecl(DupDecls[I]).Precedence then
        Fail(TDecl(DupDecls[I]).Module, TDecl(DupDecls[I]).Element, 'XTSE0770', 'two functions ' +
          LandrixXmlUtf8ToString(TXsltTemplate(DupTemplates[I]).Name) + ' with the same arity and precedence');
  finally
    DupDecls.Free;
    DupTemplates.Free;
    Keys.Free;
  end;
end;

{ The parameters and body of a stylesheet function (no focus inside; a
  parameter has neither select nor content: XTSE0760). }
procedure TCompiler.CompileFunction(T: TXsltTemplate; D: TDecl);
var
  M: TModule;
  E, C, I: Integer;
  V: TLandrixXmlUtf8;
  Scope: TScope;
  P: TXsltInstr;
begin
  M := D.Module;
  E := D.Element;
  T.Params.Clear;
  if Attr(M, E, 'override', V) and (Trim8(V) <> 'yes') and (Trim8(V) <> 'no') then
    Fail(M, E, 'XTSE0020', 'override must be yes or no');
  Scope := TScope.Create;
  try
    Scope.NextSlot := FC.GlobalCount;
    Scope.MaxSlot := FC.GlobalCount;
    T.HasAs := ParseType(M, E, Scope, T.AsType);
    C := M.Tree.FirstChild(E);
    while C >= 0 do
    begin
      if IsXsl(M, C, 'param') then
      begin
        if Attr(M, C, 'required', V) then
          Fail(M, C, 'XTSE0020', 'a parameter of a function has no required attribute');
        P := CompileVariable(M, C, Scope, True);
        { tunnel="no" is accepted, as Saxon does }
        if P.Tunnel then
        begin
          P.Free;
          Fail(M, C, 'XTSE0020', 'a parameter of a function cannot be a tunnel parameter');
        end;
        if (P.Select <> nil) or (P.Body.Count > 0) then
        begin
          P.Free;
          Fail(M, C, 'XTSE0760', 'a parameter of a function has no default value');
        end;
        for I := 0 to Integer(T.Params.Count) - 1 do
          if TXsltInstr(T.Params[I]).VarName = P.VarName then
          begin
            P.Free;
            Fail(M, C, 'XTSE0580', 'two parameters of a function have the same name');
          end;
        T.Params.Add(P);
      end
      else if (M.Tree.Kind[C] = xnkElement) or
        ((M.Tree.Kind[C] = xnkText) and ((Trim8(M.Tree.ValueUtf8(C)) <> '') or PreservesSpace(M.Tree, C))) then
        Break;
      C := M.Tree.NextSibling[C];
    end;
    if C >= 0 then
      CompileBody(M, E, Scope, T.Body, C);
    T.FrameSize := Scope.MaxSlot;
  finally
    Scope.Free;
  end;
end;

procedure TCompiler.CompileTemplate(D: TDecl);
var
  T: TXsltTemplate;
  M: TModule;
  E, C, I: Integer;
  V, Match, Modes: TLandrixXmlUtf8;
  Scope: TScope;
  P: TXsltInstr;
  HasMatch, HasModes: Boolean;
begin
  M := D.Module;
  E := D.Element;
  T := TXsltTemplate.Create;
  FC.Templates.Add(T);
  T.Module := M.Uri;
  T.Line := M.LineOf(E);
  T.Column := M.ColumnOf(E);
  T.Precedence := D.Precedence;
  if Attr(M, E, 'name', V) then
    T.Name := DeclName(M, E, V);
  Match := '';
  HasMatch := Attr(M, E, 'match', Match);
  if not HasMatch and (T.Name = '') then
    Fail(M, E, 'XTSE0500', 'xsl:template needs a match or name attribute');
  if HasMatch and (Trim8(Match) = '') then
    Fail(M, E, 'XTSE0340', 'an empty pattern');
  Modes := '';
  HasModes := Attr(M, E, 'mode', Modes);
  if HasModes and not HasMatch then
    Fail(M, E, 'XTSE0500', 'xsl:template with a mode needs a match attribute');
  if not HasMatch and Attr(M, E, 'priority', V) then
    Fail(M, E, 'XTSE0500', 'xsl:template with a priority needs a match attribute');
  Scope := TScope.Create;
  try
    Scope.NextSlot := FC.GlobalCount;
    Scope.MaxSlot := FC.GlobalCount;
    T.HasAs := ParseType(M, E, Scope, T.AsType);
    { the parameters, then the body after them }
    C := M.Tree.FirstChild(E);
    while C >= 0 do
    begin
      if IsXsl(M, C, 'param') then
      begin
        P := CompileVariable(M, C, Scope, True);
        for I := 0 to Integer(T.Params.Count) - 1 do
          if TXsltInstr(T.Params[I]).VarName = P.VarName then
          begin
            P.Free;
            Fail(M, C, 'XTSE0580', 'two parameters of a template have the same name');
          end;
        T.Params.Add(P);
      end
      else if (M.Tree.Kind[C] = xnkElement) or
        ((M.Tree.Kind[C] = xnkText) and ((Trim8(M.Tree.ValueUtf8(C)) <> '') or PreservesSpace(M.Tree, C))) then
        Break;
      C := M.Tree.NextSibling[C];
    end;
    if C >= 0 then
      CompileBody(M, E, Scope, T.Body, C);
    T.FrameSize := Scope.MaxSlot;
  finally
    Scope.Free;
  end;
  if HasMatch then
    AddRules(D, T, Match, Modes, HasModes);
  if T.Name <> '' then
  begin
    if FC.NamedTemplates.Find(LandrixXmlUtf8ToKey(T.Name), I) then
    begin
      if TXsltTemplate(FC.NamedTemplates.Objects[I]).Precedence = T.Precedence then
      begin
        FDupTemplates.Add(T);
        FDupTemplateDecls.Add(D);
      end;
      if TXsltTemplate(FC.NamedTemplates.Objects[I]).Precedence < T.Precedence then
        FC.NamedTemplates.Objects[I] := T;
    end
    else
      FC.NamedTemplates.AddObject(LandrixXmlUtf8ToKey(T.Name), T);
  end;
end;

{ whether S is a QName (prefix:local or local) }
function IsQName8(const S: TLandrixXmlUtf8): Boolean;
var
  K: Integer;
begin
  K := Pos8(':', S);
  if K = 0 then
    Result := IsNCName8(S)
  else
    Result := IsNCName8(Copy(S, 1, K - 1)) and IsNCName8(Copy(S, K + 1, Length(S) - K));
end;

{ use-attribute-sets: the names (QNames separated by white space, no
  default namespace) as an xskUseAttributeSets, resolved by Finish; nil
  for an empty list (a name that is no QName: XTSE0710, as in Saxon) }
function TCompiler.UseAttributeSets(M: TModule; E: Integer; const Names: TLandrixXmlUtf8): TXsltInstr;
var
  I, J, N: Integer;
  S: TLandrixXmlUtf8;
begin
  Result := nil;
  S := Names;
  I := 1;
  N := 0;
  while I <= Length(S) do
  begin
    while (I <= Length(S)) and (S[I] in [' ', #9, #10, #13]) do
      Inc(I);
    if I > Length(S) then
      Break;
    J := I;
    while (J <= Length(S)) and not (S[J] in [' ', #9, #10, #13]) do
      Inc(J);
    if Result = nil then
      Result := NewInstr(xskUseAttributeSets, M, E);
    SetLength(Result.SetNames, N + 1);
    try
      if not IsQName8(Copy(S, I, J - I)) then
        Fail(M, E, 'XTSE0710', 'not a QName in use-attribute-sets: "' + LandrixXmlUtf8ToString(Copy(S, I, J - I)) + '"');
      Result.SetNames[N] := QNameToClark(M, E, Copy(S, I, J - I), False);
    except
      Result.Free;
      raise;
    end;
    Inc(N);
    I := J;
  end;
end;

{ xsl:attribute-set: a TXsltTemplate of its own (Body: the attribute sets
  it uses, then its xsl:attribute instructions), added to the declarations
  of its name in order of import precedence, then declaration order }
procedure TCompiler.CompileAttributeSet(D: TDecl);
var
  T: TXsltTemplate;
  M: TModule;
  E, C, P, K: Integer;
  V, A: TLandrixXmlUtf8;
  Scope: TScope;
  I: TXsltInstr;
  L: TList;
begin
  M := D.Module;
  E := D.Element;
  for K := E + 1 to E + M.Tree.AttributeCount[E] do
  begin
    if M.Tree.NamespaceUriUtf8(K) <> '' then
      Continue;
    A := M.Tree.LocalNameUtf8(K);
    { the standard attributes (CheckStandard) and those of XSLT 3.0 }
    if not ((A = 'name') or (A = 'use-attribute-sets') or (A = 'visibility') or (A = 'streamable') or
      (A = 'version') or (A = 'exclude-result-prefixes') or (A = 'extension-element-prefixes') or
      (A = 'xpath-default-namespace') or (A = 'default-collation') or (A = 'use-when') or
      (A = 'expand-text') or (A = 'default-mode') or (A = 'default-validation') or
      (A = 'input-type-annotations')) and not Forwards(M, E) then
      Fail(M, E, 'XTSE0090', 'xsl:attribute-set has no attribute ' + LandrixXmlUtf8ToString(A));
  end;
  V := Trim8(ReqAttr(M, E, 'name'));
  if not IsQName8(V) then
    Fail(M, E, 'XTSE0020', 'the name of xsl:attribute-set is not a QName: "' + LandrixXmlUtf8ToString(V) + '"');
  T := TXsltTemplate.Create;
  FC.Templates.Add(T);
  T.Name := DeclName(M, E, V);
  T.Module := M.Uri;
  T.Line := M.LineOf(E);
  T.Column := M.ColumnOf(E);
  T.Precedence := D.Precedence;
  if Attr(M, E, 'use-attribute-sets', V) then
  begin
    I := UseAttributeSets(M, E, V);
    if I <> nil then
      T.Body.Add(I);
  end;
  Scope := TScope.Create;
  try
    Scope.NextSlot := FC.GlobalCount;
    Scope.MaxSlot := FC.GlobalCount;
    C := M.Tree.FirstChild(E);
    while C >= 0 do
    begin
      if M.Tree.Kind[C] = xnkElement then
      begin
        if not IsXsl(M, C, 'attribute') then
          Fail(M, C, 'XTSE0010', 'xsl:attribute-set contains xsl:attribute only');
        I := CompileInstr(M, C, Scope);
        if I <> nil then
          T.Body.Add(I);
      end
      else if (M.Tree.Kind[C] = xnkText) and (Trim8(M.Tree.ValueUtf8(C)) <> '') then
        Fail(M, E, 'XTSE0010', 'text in xsl:attribute-set');
      C := M.Tree.NextSibling[C];
    end;
    T.FrameSize := Scope.MaxSlot;
  finally
    Scope.Free;
  end;
  if not FC.AttributeSets.Find(LandrixXmlUtf8ToKey(T.Name), P) then
    P := FC.AttributeSets.AddObject(LandrixXmlUtf8ToKey(T.Name), TList.Create);
  L := TList(FC.AttributeSets.Objects[P]);
  K := Integer(L.Count);
  while (K > 0) and (TXsltTemplate(L[K - 1]).Precedence > T.Precedence) do
    Dec(K);
  L.Insert(K, T);
end;

{ use-character-maps: the names (QNames separated by white space, no
  default namespace) as Clark names; XTSE0020 for one that is no QName }
function TCompiler.MapNames(M: TModule; E: Integer; const Names: TLandrixXmlUtf8): TLandrixXmlUtf8Array;
var
  I, J, N: Integer;
begin
  Result := nil;
  I := 1;
  N := 0;
  while I <= Length(Names) do
  begin
    while (I <= Length(Names)) and (Names[I] in [' ', #9, #10, #13]) do
      Inc(I);
    if I > Length(Names) then
      Break;
    J := I;
    while (J <= Length(Names)) and not (Names[J] in [' ', #9, #10, #13]) do
      Inc(J);
    if not IsQName8(Copy(Names, I, J - I)) then
      Fail(M, E, 'XTSE0020', 'not a QName in use-character-maps: "' +
        LandrixXmlUtf8ToString(Copy(Names, I, J - I)) + '"');
    SetLength(Result, N + 1);
    Result[N] := QNameToClark(M, E, Copy(Names, I, J - I), False);
    Inc(N);
    I := J;
  end;
end;

procedure TCompiler.AddMapRef(Props: TXsltOutputProperties; M: TModule; E: Integer; const Names: TLandrixXmlUtf8);
var
  R: TMapRef;
  N: TLandrixXmlUtf8Array;
begin
  N := MapNames(M, E, Names);
  R := TMapRef.Create;
  FMapRefs.Add(R);
  R.Props := Props;
  R.Module := M;
  R.Element := E;
  R.Names := N;
end;

{ xsl:character-map with its xsl:output-character children; of several
  of one name the one of the highest import precedence (two of the same
  are XTSE1580 when FinishCharacterMaps finds no higher one) }
procedure TCompiler.CompileCharacterMap(D: TDecl);
var
  M: TModule;
  E, C, K, P, N, Len: Integer;
  A, V, Name: TLandrixXmlUtf8;
  Map: TCharMap;
  Code: Cardinal;
  Old: TCharMap;
begin
  M := D.Module;
  E := D.Element;
  for K := E + 1 to E + M.Tree.AttributeCount[E] do
  begin
    if M.Tree.NamespaceUriUtf8(K) <> '' then
      Continue;
    A := M.Tree.LocalNameUtf8(K);
    if not ((A = 'name') or (A = 'use-character-maps') or (A = 'version') or
      (A = 'exclude-result-prefixes') or (A = 'extension-element-prefixes') or
      (A = 'xpath-default-namespace') or (A = 'default-collation') or (A = 'use-when') or
      (A = 'expand-text') or (A = 'default-mode') or (A = 'default-validation') or
      (A = 'input-type-annotations')) and not Forwards(M, E) then
      Fail(M, E, 'XTSE0090', 'xsl:character-map has no attribute ' + LandrixXmlUtf8ToString(A));
  end;
  V := Trim8(ReqAttr(M, E, 'name'));
  if not IsQName8(V) then
    Fail(M, E, 'XTSE0020', 'the name of xsl:character-map is not a QName: "' + LandrixXmlUtf8ToString(V) + '"');
  Name := DeclName(M, E, V);
  Map := TCharMap.Create;
  try
    Map.Module := M;
    Map.Element := E;
    Map.Precedence := D.Precedence;
    if Attr(M, E, 'use-character-maps', V) then
      Map.UseNames := MapNames(M, E, V);
    N := 0;
    C := M.Tree.FirstChild(E);
    while C >= 0 do
    begin
      if M.Tree.Kind[C] = xnkElement then
      begin
        if not IsXsl(M, C, 'output-character') then
          Fail(M, C, 'XTSE0010', 'xsl:character-map contains xsl:output-character only');
        for K := C + 1 to C + M.Tree.AttributeCount[C] do
        begin
          if M.Tree.NamespaceUriUtf8(K) <> '' then
            Continue;
          A := M.Tree.LocalNameUtf8(K);
          if not ((A = 'character') or (A = 'string') or (A = 'version') or
            (A = 'exclude-result-prefixes') or (A = 'extension-element-prefixes') or
            (A = 'xpath-default-namespace') or (A = 'default-collation') or (A = 'use-when') or
            (A = 'expand-text') or (A = 'default-mode') or (A = 'default-validation') or
            (A = 'input-type-annotations')) and not Forwards(M, C) then
            Fail(M, C, 'XTSE0090', 'xsl:output-character has no attribute ' + LandrixXmlUtf8ToString(A));
        end;
        { one character, as it is (no white space trimmed) }
        V := ReqAttr(M, C, 'character');
        Len := 0;
        Code := 0;
        if V <> '' then
          Len := LandrixXmlDecodeUtf8(PAnsiChar(V), Length(V), Code);
        if V = '' then
          Fail(M, C, 'XTSE0020', 'the character of xsl:output-character is empty');
        if (Len = 0) or (Len <> Length(V)) then
          Fail(M, C, 'XTSE0020', 'the character of xsl:output-character must be a single character');
        SetLength(Map.Chars, N + 1);
        SetLength(Map.Strings, N + 1);
        Map.Chars[N] := Code;
        Map.Strings[N] := ReqAttr(M, C, 'string');
        Inc(N);
      end
      else if (M.Tree.Kind[C] = xnkText) and (Trim8(M.Tree.ValueUtf8(C)) <> '') then
        Fail(M, E, 'XTSE0010', 'xsl:character-map contains xsl:output-character only');
      C := M.Tree.NextSibling[C];
    end;
  except
    Map.Free;
    raise;
  end;
  if FCharMaps.Find(LandrixXmlUtf8ToKey(Name), P) then
  begin
    Old := TCharMap(FCharMaps.Objects[P]);
    if Old.Precedence = Map.Precedence then
    begin
      KeepMapNames(Map);
      Map.Free;
      Old.Duplicate := True;
    end
    else if Old.Precedence > Map.Precedence then
    begin
      KeepMapNames(Map);
      Map.Free;
    end
    else
    begin
      KeepMapNames(Old);
      Old.Free;
      FCharMaps.Objects[P] := Map;
    end;
  end
  else
    FCharMaps.AddObject(LandrixXmlUtf8ToKey(Name), Map);
end;

{ the names a map that is not used (another one of its name replaces it)
  refers to: still checked (XTSE1590), nothing composed }
procedure TCompiler.KeepMapNames(Map: TCharMap);
var
  R: TMapRef;
begin
  if Length(Map.UseNames) = 0 then
    Exit;
  R := TMapRef.Create;
  FMapRefs.Add(R);
  R.Module := Map.Module;
  R.Element := Map.Element;
  R.Names := Map.UseNames;
end;

{ the mappings of Map into Props: those of its maps first, then its own }
procedure TCompiler.ComposeMap(Map: TCharMap; Props: TXsltOutputProperties);
var
  I, P: Integer;
begin
  for I := 0 to Integer(Length(Map.UseNames)) - 1 do
    if FCharMaps.Find(LandrixXmlUtf8ToKey(Map.UseNames[I]), P) then
      ComposeMap(TCharMap(FCharMaps.Objects[P]), Props);
  for I := 0 to Integer(Length(Map.Chars)) - 1 do
    Props.AddMapping(Map.Chars[I], Map.Strings[I]);
end;

{ XTSE1590 for a character map name that is not declared, XTSE1600 for a
  map that uses itself; then the maps of each use-character-maps composed
  into its output properties }
procedure TCompiler.FinishCharacterMaps;
var
  I, J, P: Integer;
  R: TMapRef;
  Map: TCharMap;
  Path, Done: TStringList;

  procedure Check(Map: TCharMap; const Name: TLandrixXmlUtf8);
  var
    K, Q: Integer;
  begin
    if Done.IndexOf(LandrixXmlUtf8ToKey(Name)) >= 0 then
      Exit;
    if Path.IndexOf(LandrixXmlUtf8ToKey(Name)) >= 0 then
      Fail(Map.Module, Map.Element, 'XTSE1600', 'the character map ' + LandrixXmlUtf8ToString(Name) +
        ' uses itself');
    Path.Add(LandrixXmlUtf8ToKey(Name));
    for K := 0 to Integer(Length(Map.UseNames)) - 1 do
    begin
      if not FCharMaps.Find(LandrixXmlUtf8ToKey(Map.UseNames[K]), Q) then
        Fail(Map.Module, Map.Element, 'XTSE1590', 'no character map named ' +
          LandrixXmlUtf8ToString(Map.UseNames[K]));
      Check(TCharMap(FCharMaps.Objects[Q]), Map.UseNames[K]);
    end;
    Path.Delete(Path.Count - 1);
    Done.Add(LandrixXmlUtf8ToKey(Name));
  end;

begin
  for I := 0 to Integer(FCharMaps.Count) - 1 do
  begin
    Map := TCharMap(FCharMaps.Objects[I]);
    if Map.Duplicate then
      Fail(Map.Module, Map.Element, 'XTSE1580', 'two character maps named ' +
        LandrixXmlUtf8ToString(LandrixXmlKeyToUtf8(FCharMaps[I])) + ' with the same import precedence');
  end;
  Path := TXsltStringList.Create;
  Done := TXsltStringList.Create;
  try
    Path.CaseSensitive := True;
    Done.CaseSensitive := True;
    Done.Sorted := True;
    for I := 0 to Integer(FCharMaps.Count) - 1 do
      Check(TCharMap(FCharMaps.Objects[I]), LandrixXmlKeyToUtf8(FCharMaps[I]));
  finally
    Done.Free;
    Path.Free;
  end;
  for I := 0 to Integer(FMapRefs.Count) - 1 do
  begin
    R := TMapRef(FMapRefs[I]);
    for J := 0 to Integer(Length(R.Names)) - 1 do
    begin
      if not FCharMaps.Find(LandrixXmlUtf8ToKey(R.Names[J]), P) then
        Fail(R.Module, R.Element, 'XTSE1590', 'no character map named ' + LandrixXmlUtf8ToString(R.Names[J]));
      Map := TCharMap(FCharMaps.Objects[P]);
      if R.Props <> nil then
        ComposeMap(Map, R.Props);
    end;
  end;
end;

{ xsl:namespace-alias: #default for the default namespace (none: no
  namespace); of several for one stylesheet namespace the one of the
  highest import precedence (two of the same with different result
  namespaces are XTSE0810 when Finish finds no higher one; Saxon reports
  it also when a higher one replaces both. Saxon difference:
  alias-precedence) }
procedure TCompiler.CompileNamespaceAlias(D: TDecl);
var
  M: TModule;
  E, K, P: Integer;
  A, V, SUri, RPrefix, RUri: TLandrixXmlUtf8;
  Alias: TNamespaceAlias;
begin
  M := D.Module;
  E := D.Element;
  for K := E + 1 to E + M.Tree.AttributeCount[E] do
  begin
    if M.Tree.NamespaceUriUtf8(K) <> '' then
      Continue;
    A := M.Tree.LocalNameUtf8(K);
    if not ((A = 'stylesheet-prefix') or (A = 'result-prefix') or (A = 'version') or
      (A = 'exclude-result-prefixes') or (A = 'extension-element-prefixes') or
      (A = 'xpath-default-namespace') or (A = 'default-collation') or (A = 'use-when') or
      (A = 'expand-text') or (A = 'default-mode') or (A = 'default-validation') or
      (A = 'input-type-annotations')) and not Forwards(M, E) then
      Fail(M, E, 'XTSE0090', 'xsl:namespace-alias has no attribute ' + LandrixXmlUtf8ToString(A));
  end;
  V := Trim8(ReqAttr(M, E, 'stylesheet-prefix'));
  if V = '#default' then
  begin
    if not M.Tree.LookupNamespace(E, '', SUri) then
      SUri := '';
  end
  else if not M.Tree.LookupNamespace(E, V, SUri) then
    Fail(M, E, 'XTSE0812', 'the stylesheet-prefix ' + LandrixXmlUtf8ToString(V) + ' is not declared');
  V := Trim8(ReqAttr(M, E, 'result-prefix'));
  if V = '#default' then
  begin
    RPrefix := '';
    if not M.Tree.LookupNamespace(E, '', RUri) then
      RUri := '';
  end
  else
  begin
    RPrefix := V;
    if not M.Tree.LookupNamespace(E, V, RUri) then
      Fail(M, E, 'XTSE0812', 'the result-prefix ' + LandrixXmlUtf8ToString(V) + ' is not declared');
  end;
  if FAliases.Find(LandrixXmlUtf8ToKey(SUri), P) then
  begin
    Alias := TNamespaceAlias(FAliases.Objects[P]);
    if Alias.Precedence > D.Precedence then
      Exit;
    if Alias.Precedence = D.Precedence then
    begin
      if Alias.Uri <> RUri then
        Alias.Conflict := True;
      Exit;
    end;
    Alias.Conflict := False;
  end
  else
  begin
    Alias := TNamespaceAlias.Create;
    FAliases.AddObject(LandrixXmlUtf8ToKey(SUri), Alias);
  end;
  Alias.Prefix := RPrefix;
  Alias.Uri := RUri;
  Alias.Precedence := D.Precedence;
  Alias.Module := M;
  Alias.Element := E;
end;

{ the namespace aliases for a literal result element: the names of the
  element and of its attributes in a stylesheet namespace get the result
  namespace and prefix, its namespace nodes for it become the result
  namespace (replacing another binding of the result prefix, as Saxon) }
procedure TCompiler.ApplyAlias(Instr: TXsltInstr);

  function IsAliasResult(const Uri: TLandrixXmlUtf8): Boolean;
  var
    K: Integer;
  begin
    Result := True;
    for K := 0 to Integer(FAliases.Count) - 1 do
      if (Uri <> '') and (TNamespaceAlias(FAliases.Objects[K]).Uri = Uri) then
        Exit;
    Result := False;
  end;

var
  I, J, P, Count: Integer;
  Alias: TNamespaceAlias;
  T: TXsltAttributeTemplate;
  Prefixes, Uris: TLandrixXmlUtf8Array;
  Mapped: array of Boolean;
begin
  if FAliases.Find(LandrixXmlUtf8ToKey(Instr.NamespaceUri), P) then
  begin
    Alias := TNamespaceAlias(FAliases.Objects[P]);
    Instr.NamespaceUri := Alias.Uri;
    Instr.Prefix := Alias.Prefix;
  end;
  for I := 0 to Integer(Instr.Attributes.Count) - 1 do
  begin
    T := TXsltAttributeTemplate(Instr.Attributes[I]);
    if (T.NamespaceUri <> '') and FAliases.Find(LandrixXmlUtf8ToKey(T.NamespaceUri), P) then
    begin
      Alias := TNamespaceAlias(FAliases.Objects[P]);
      T.NamespaceUri := Alias.Uri;
      T.Prefix := Alias.Prefix;
      if Alias.Uri = '' then
        T.Prefix := '';
    end;
  end;
  { the namespace nodes: the aliased ones first decided, then the others
    unless they bind a prefix an aliased one takes }
  Mapped := nil;
  Prefixes := Copy(Instr.NsPrefixes, 0, Length(Instr.NsPrefixes));
  Uris := Copy(Instr.NsUris, 0, Length(Instr.NsUris));
  { an excluded namespace that is aliased, or the result of an alias,
    is copied all the same (XSLT 2.0 11.1.4, Saxon) }
  for I := 0 to Integer(Length(Instr.ExPrefixes)) - 1 do
    if FAliases.Find(LandrixXmlUtf8ToKey(Instr.ExUris[I]), P) or IsAliasResult(Instr.ExUris[I]) then
    begin
      J := Integer(Length(Prefixes));
      SetLength(Prefixes, J + 1);
      SetLength(Uris, J + 1);
      Prefixes[J] := Instr.ExPrefixes[I];
      Uris[J] := Instr.ExUris[I];
    end;
  SetLength(Mapped, Length(Prefixes));
  for I := 0 to Integer(Length(Prefixes)) - 1 do
  begin
    Mapped[I] := FAliases.Find(LandrixXmlUtf8ToKey(Uris[I]), P);
    if Mapped[I] then
    begin
      Alias := TNamespaceAlias(FAliases.Objects[P]);
      Prefixes[I] := Alias.Prefix;
      Uris[I] := Alias.Uri;
      { an alias to no namespace declares nothing }
      if Uris[I] = '' then
      begin
        Mapped[I] := False;
        Prefixes[I] := #0;
      end;
    end;
  end;
  Count := 0;
  SetLength(Instr.NsPrefixes, Length(Prefixes));
  SetLength(Instr.NsUris, Length(Prefixes));
  for I := 0 to Integer(Length(Prefixes)) - 1 do
  begin
    if Prefixes[I] = #0 then
      Continue;
    if not Mapped[I] then
      for J := 0 to Integer(Length(Prefixes)) - 1 do
        if Mapped[J] and (Prefixes[J] = Prefixes[I]) then
          Prefixes[I] := #0;
    if Prefixes[I] = #0 then
      Continue;
    { once per binding }
    for J := 0 to Count - 1 do
      if Instr.NsPrefixes[J] = Prefixes[I] then
        Prefixes[I] := #0;
    if Prefixes[I] = #0 then
      Continue;
    Instr.NsPrefixes[Count] := Prefixes[I];
    Instr.NsUris[Count] := Uris[I];
    Inc(Count);
  end;
  SetLength(Instr.NsPrefixes, Count);
  SetLength(Instr.NsUris, Count);
end;

{ the document element of a module: xsl:stylesheet or xsl:transform, or
  a literal result element with xsl:version (a simplified stylesheet
  module; XTSE0150 without it, and for another XSLT element or an
  extension instruction, where Saxon reports XPST0010. Saxon difference:
  simplified-root) }
procedure TCompiler.CheckRoot(M: TModule);
var
  E, A: Integer;
  Found: Boolean;
  V: TLandrixXmlUtf8;
begin
  E := M.Tree.DocumentElement;
  if E < 0 then
    Fail(M, -1, 'XTSE0150', 'the stylesheet has no element');
  if IsXsl(M, E, 'stylesheet') or IsXsl(M, E, 'transform') then
  begin
    { also in an included or imported module }
    if not Attr(M, E, 'version', V) then
      Fail(M, E, 'XTSE0010', 'xsl:stylesheet needs a version attribute');
    Exit;
  end;
  Found := False;
  for A := E + 1 to E + M.Tree.AttributeCount[E] do
    if (M.Tree.NamespaceUriUtf8(A) = XsltNamespace) and (M.Tree.LocalNameUtf8(A) = 'version') then
      Found := True;
  if (M.Tree.NamespaceUriUtf8(E) = XsltNamespace) or not Found then
    Fail(M, E, 'XTSE0150', 'the document element is neither xsl:stylesheet nor a literal result element ' +
      'with xsl:version');
  { an extension instruction is no literal result element (Saxon:
    XPST0010) }
  if IsExtension(M, E) then
    Fail(M, E, 'XTSE0150', 'the document element of a simplified stylesheet module is an extension instruction');
  { the document element is not subject to use-when: XTSE0150 whatever
    its value (Saxon accepts true() and reports XPST0010 for false().
    Saxon difference: simplified-root) }
  for A := E + 1 to E + M.Tree.AttributeCount[E] do
    if (M.Tree.NamespaceUriUtf8(A) = XsltNamespace) and (M.Tree.LocalNameUtf8(A) = 'use-when') then
      Fail(M, E, 'XTSE0150', 'xsl:use-when on the document element of a simplified stylesheet module');
  M.Simplified := True;
end;

{ a simplified stylesheet module: a template rule for "/" whose body is
  the literal result element }
procedure TCompiler.CompileSimplified(D: TDecl);
var
  T: TXsltTemplate;
  M: TModule;
  Scope: TScope;
  I: TXsltInstr;
begin
  M := D.Module;
  T := TXsltTemplate.Create;
  FC.Templates.Add(T);
  T.Module := M.Uri;
  T.Line := M.LineOf(D.Element);
  T.Column := M.ColumnOf(D.Element);
  T.Precedence := D.Precedence;
  Scope := TScope.Create;
  try
    Scope.NextSlot := FC.GlobalCount;
    Scope.MaxSlot := FC.GlobalCount;
    I := CompileLiteral(M, D.Element, Scope);
    T.Body.Add(I);
    T.FrameSize := Scope.MaxSlot;
  finally
    Scope.Free;
  end;
  AddRules(D, T, '/', '', False);
end;

procedure TCompiler.CompileOutput(D: TDecl);
var
  I, P, K: Integer;
  M: TModule;
  L, V, Name, Bad: TLandrixXmlUtf8;
  Target: TXsltOutputProperties;
  Prefixes, Uris: TLandrixXmlUtf8Array;
begin
  M := D.Module;
  Prefixes := nil;
  Uris := nil;
  { a named one: its own definition, the unnamed ones the default }
  Target := FC.Output;
  if Attr(M, D.Element, 'name', Name) then
  begin
    { a QName or an EQName (as Saxon accepts it) }
    if Copy(Trim8(Name), 1, 2) = 'Q{' then
    begin
      Name := XsltFormatClark(Trim8(Name), nil, nil);
      if Name = '' then
        Fail(M, D.Element, 'XTSE0020', 'the name of xsl:output is not a valid EQName');
      if (Copy(Name, 1, 1) = '{') and ReservedNamespace(Copy(Name, 2, Pos8('}', Name) - 2)) then
        Fail(M, D.Element, 'XTSE0080', 'the name of xsl:output is in a reserved namespace');
    end
    else
      Name := DeclName(M, D.Element, Trim8(Name));
    if FC.NamedOutputs.Find(LandrixXmlUtf8ToKey(Name), P) then
      Target := TXsltOutputProperties(FC.NamedOutputs.Objects[P])
    else
    begin
      Target := TXsltOutputProperties.Create;
      FC.NamedOutputs.AddObject(LandrixXmlUtf8ToKey(Name), Target);
    end;
  end;
  for I := D.Element + 1 to D.Element + M.Tree.AttributeCount[D.Element] do
  begin
    if M.Tree.NamespaceUriUtf8(I) <> '' then
      Continue;
    L := M.Tree.LocalNameUtf8(I);
    { standard attributes (CheckStandard) }
    if (L = 'exclude-result-prefixes') or (L = 'extension-element-prefixes') or (L = 'expand-text') or
      (L = 'xpath-default-namespace') or (L = 'use-when') or (L = 'default-mode') or
      (L = 'default-collation') then
      Continue;
    if L = 'name' then
      Continue;
    if L = 'use-character-maps' then
    begin
      { the maps of every xsl:output are used, in declaration order }
      AddMapRef(Target, M, D.Element, M.Tree.ValueUtf8(I));
      Continue;
    end;
    if L = 'cdata-section-elements' then
    begin
      { the union of every xsl:output's }
      Prefixes := M.Tree.InScopePrefixesUtf8(D.Element);
      SetLength(Uris, Length(Prefixes));
      for K := 0 to Integer(Length(Prefixes)) - 1 do
        M.Tree.LookupNamespace(D.Element, Prefixes[K], Uris[K]);
      if not XsltCDataNames(M.Tree.ValueUtf8(I), Prefixes, Uris, V, Bad) then
        Fail(M, D.Element, 'XTSE0020', 'not a QName (or its prefix is not declared) in cdata-section-elements: "' +
          LandrixXmlUtf8ToString(Bad) + '"');
      Target.AddCDataElements(V);
      Continue;
    end;
    V := Trim8(M.Tree.ValueUtf8(I));
    case XsltOutputPropertyStatus(L, V) of
      xosUnsupported:
        Unsupported(M, D.Element, 'xsl:output ' + LandrixXmlUtf8ToString(L) + '="' + LandrixXmlUtf8ToString(V) + '"');
      xosUnknown:
        begin
          { forwards compatible: an unknown attribute is ignored }
          if not Forwards(M, D.Element) then
            Fail(M, D.Element, 'XTSE0090', 'xsl:output has no attribute ' + LandrixXmlUtf8ToString(L));
          Continue;
        end;
      xosInvalid:
        Fail(M, D.Element, 'XTSE0020', 'xsl:output ' + LandrixXmlUtf8ToString(L) + '="' +
          LandrixXmlUtf8ToString(V) + '" is not a valid value');
    else
      { supported }
    end;
    { compared as stored: yes, true and 1 are equal for the yes/no
      properties only }
    Target.SetValue(L, V);
    OutputSeen(D, Name + ' ' + L, Target.Value(L, V));
  end;
end;

{ records an explicit output property; D comes in ascending import
  precedence, so a higher one replaces the earlier ones and their conflict }
procedure TCompiler.OutputSeen(D: TDecl; const Key, Value: TLandrixXmlUtf8);
var
  I: Integer;
  S: TOutputSeen;
  V: TLandrixXmlUtf8;
begin
  V := Value;
  for I := 0 to Integer(FOutputSeen.Count) - 1 do
  begin
    S := TOutputSeen(FOutputSeen[I]);
    if S.Key = Key then
    begin
      if D.Precedence > S.Decl.Precedence then
      begin
        S.Decl := D;
        S.Value := V;
        S.Conflict := nil;
      end
      else if (D.Precedence = S.Decl.Precedence) and (V <> S.Value) and (S.Conflict = nil) then
        S.Conflict := D;
      Exit;
    end;
  end;
  S := TOutputSeen.Create;
  FOutputSeen.Add(S);
  S.Key := Key;
  S.Decl := D;
  S.Value := V;
end;

{ Call targets, modes for #all, rule order. }
procedure TCompiler.Finish;
var
  I, J, K: Integer;
  Mode: TXsltMode;
  Instr: TXsltInstr;
  V: TLandrixXmlUtf8;

  { every required parameter of the called template is supplied }
  procedure CheckRequired(Instr: TXsltInstr);
  var
    A, B: Integer;
    P: TXsltInstr;
    Found: Boolean;
  begin
    for A := 0 to Integer(TXsltTemplate(Instr.Template).Params.Count) - 1 do
    begin
      P := TXsltInstr(TXsltTemplate(Instr.Template).Params[A]);
      { a required tunnel parameter is checked when it is called (XTDE0700) }
      if not P.Required or P.Tunnel then
        Continue;
      Found := False;
      for B := 0 to Integer(Instr.Params.Count) - 1 do
        if (TXsltWithParam(Instr.Params[B]).Name = P.VarName) and not TXsltWithParam(Instr.Params[B]).Tunnel then
          Found := True;
      if not Found then
        raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTSE0690', 'the required parameter ' +
          LandrixXmlUtf8ToString(P.VarName) + ' is not supplied', Instr.Module, Instr.Line, Instr.Column);
    end;
    for B := 0 to Integer(Instr.Params.Count) - 1 do
    begin
      { a tunnel parameter may be meant for a template called further on }
      if TXsltWithParam(Instr.Params[B]).Tunnel then
        Continue;
      Found := False;
      for A := 0 to Integer(TXsltTemplate(Instr.Template).Params.Count) - 1 do
        if (TXsltInstr(TXsltTemplate(Instr.Template).Params[A]).VarName = TXsltWithParam(Instr.Params[B]).Name) and
          not TXsltInstr(TXsltTemplate(Instr.Template).Params[A]).Tunnel then
          Found := True;
      { backwards compatible mode: a parameter the template does not
        declare is ignored }
      if not Found and not Instr.Backwards then
        raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTSE0680', 'the template ' +
          LandrixXmlUtf8ToString(TXsltTemplate(Instr.Template).Name) + ' has no parameter ' +
          LandrixXmlUtf8ToString(TXsltWithParam(Instr.Params[B]).Name), Instr.Module, Instr.Line, Instr.Column);
    end;
  end;

  { the declarations the names of an xskUseAttributeSets expand to }
  procedure ResolveSets(Instr: TXsltInstr);
  var
    N, P, A: Integer;
    L: TList;
  begin
    Instr.Sets := TList.Create;
    for N := 0 to Integer(Length(Instr.SetNames)) - 1 do
    begin
      if not FC.AttributeSets.Find(LandrixXmlUtf8ToKey(Instr.SetNames[N]), P) then
        raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTSE0710', 'no attribute set named ' +
          LandrixXmlUtf8ToString(Instr.SetNames[N]), Instr.Module, Instr.Line, Instr.Column);
      L := TList(FC.AttributeSets.Objects[P]);
      for A := 0 to Integer(L.Count) - 1 do
        Instr.Sets.Add(L[A]);
    end;
  end;

  { XTSE0720: an attribute set that uses itself (Path: the names being
    expanded, Done: those without a cycle) }
  procedure CheckCycle(const Name: TLandrixXmlUtf8; Path, Done: TStringList);
  var
    P, A, B: Integer;
    L: TList;
    T: TXsltTemplate;
    U: TXsltInstr;
  begin
    if Done.IndexOf(LandrixXmlUtf8ToKey(Name)) >= 0 then
      Exit;
    if not FC.AttributeSets.Find(LandrixXmlUtf8ToKey(Name), P) then
      Exit;
    L := TList(FC.AttributeSets.Objects[P]);
    if Path.IndexOf(LandrixXmlUtf8ToKey(Name)) >= 0 then
    begin
      T := TXsltTemplate(L[0]);
      raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTSE0720', 'the attribute set ' +
        LandrixXmlUtf8ToString(Name) + ' uses itself', T.Module, T.Line, T.Column);
    end;
    Path.Add(LandrixXmlUtf8ToKey(Name));
    for A := 0 to Integer(L.Count) - 1 do
    begin
      T := TXsltTemplate(L[A]);
      if (T.Body.Count = 0) or (TXsltInstr(T.Body[0]).Kind <> xskUseAttributeSets) then
        Continue;
      U := TXsltInstr(T.Body[0]);
      for B := 0 to Integer(Length(U.SetNames)) - 1 do
        CheckCycle(U.SetNames[B], Path, Done);
    end;
    Path.Delete(Path.Count - 1);
    Done.Add(LandrixXmlUtf8ToKey(Name));
  end;

  procedure CheckCycles;
  var
    N: Integer;
    Path, Done: TStringList;
  begin
    Path := TXsltStringList.Create;
    Done := TXsltStringList.Create;
    try
      Path.CaseSensitive := True;
      Done.CaseSensitive := True;
      Done.Sorted := True;
      for N := 0 to Integer(FC.AttributeSets.Count) - 1 do
        CheckCycle(LandrixXmlKeyToUtf8(FC.AttributeSets[N]), Path, Done);
    finally
      Done.Free;
      Path.Free;
    end;
  end;

  procedure Resolve(Body: TObjectList);
  var
    N, P: Integer;
    Instr: TXsltInstr;
  begin
    for N := 0 to Integer(Body.Count) - 1 do
    begin
      Instr := TXsltInstr(Body[N]);
      if (Instr.Kind = xskLiteralElement) and (FAliases.Count > 0) then
        ApplyAlias(Instr);
      if Instr.Kind = xskUseAttributeSets then
        ResolveSets(Instr);
      if Instr.UseSets <> nil then
        ResolveSets(Instr.UseSets);
      if Instr.Kind = xskCallTemplate then
      begin
        if not FC.NamedTemplates.Find(LandrixXmlUtf8ToKey(Instr.VarName), P) then
          raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTSE0650', 'no template named ' +
            LandrixXmlUtf8ToString(Instr.VarName), Instr.Module, Instr.Line, Instr.Column);
        Instr.Template := FC.NamedTemplates.Objects[P];
        CheckRequired(Instr);
      end;
      Resolve(Instr.Body);
      for P := 0 to Integer(Instr.Branches.Count) - 1 do
        Resolve(TXsltInstr(Instr.Branches[P]).Body);
      if Instr.Completion <> nil then
        Resolve(Instr.Completion.Body);
      for P := 0 to Integer(Instr.Params.Count) - 1 do
        Resolve(TXsltWithParam(Instr.Params[P]).Body);
      if Instr.SortKeys <> nil then
        for P := 0 to Integer(Instr.SortKeys.Count) - 1 do
          Resolve(TXsltSortKey(Instr.SortKeys[P]).Body);
      if Instr.NonMatching <> nil then
        Resolve(Instr.NonMatching);
    end;
  end;

begin
  FinishCharacterMaps;
  for I := 0 to Integer(FAliases.Count) - 1 do
    if TNamespaceAlias(FAliases.Objects[I]).Conflict then
      Fail(TNamespaceAlias(FAliases.Objects[I]).Module, TNamespaceAlias(FAliases.Objects[I]).Element,
        'XTSE0810', 'two xsl:namespace-alias for the namespace ' + LandrixXmlUtf8ToString(
        LandrixXmlKeyToUtf8(FAliases[I])));
  { XTDE1460 for a literal format that is not defined (or has an
    undeclared prefix), as in Saxon }
  for I := 0 to Integer(FFormatChecks.Count) - 1 do
  begin
    Instr := TXsltInstr(FFormatChecks[I]);
    V := Trim8(LiteralOf(Instr.FormatAvt));
    if not FC.NamedOutputs.Find(LandrixXmlUtf8ToKey(XsltFormatClark(V, Instr.ScopePrefixes,
      Instr.ScopeUris)), J) then
      raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTDE1460', 'no xsl:output named ' +
        LandrixXmlUtf8ToString(V), Instr.Module, Instr.Line, Instr.Column);
  end;
  CheckCycles;
  for I := 0 to Integer(FC.Templates.Count) - 1 do
  begin
    Resolve(TXsltTemplate(FC.Templates[I]).Body);
    for J := 0 to Integer(TXsltTemplate(FC.Templates[I]).Params.Count) - 1 do
      Resolve(TXsltInstr(TXsltTemplate(FC.Templates[I]).Params[J]).Body);
  end;
  for I := 0 to Integer(FC.Globals.Count) - 1 do
    Resolve(TXsltGlobal(FC.Globals[I]).Body);
  for I := 0 to Integer(FC.Keys.Count) - 1 do
    for J := 0 to Integer(TXsltKey(FC.Keys.Objects[I]).Decls.Count) - 1 do
      Resolve(TXsltKeyDecl(TXsltKey(FC.Keys.Objects[I]).Decls[J]).Body);
  ModeOf('');
  for I := 0 to Integer(FC.Modes.Count) - 1 do
  begin
    Mode := TXsltMode(FC.Modes.Objects[I]);
    for J := 0 to Integer(FAllModeTemplates.Count) - 1 do
      AddRuleToMode(Mode, TXsltRule(FAllModeTemplates[J]));
    Mode.Others.Sort(CompareRules);
    for K := 0 to Integer(Mode.Named.Count) - 1 do
      TList(Mode.Named.Objects[K]).Sort(CompareRules);
  end;
end;

{ The functions of every static context: the fixed ones, then those of
  each module. }
procedure TCompiler.AddModuleFunctions;
var
  N, I, K, F, E: Integer;
  T: TXsltTemplate;
  M: TModule;
  B: TLandrixXmlUtf8;

  procedure Add(const Uri, Name: TLandrixXmlUtf8; Arity: Integer; Flags: TLandrixXmlXPathFunctionFlags;
    Module: Integer);
  begin
    FC.FunctionUris[F] := Uri;
    FC.FunctionNames[F] := Name;
    FC.FunctionArities[F] := Arity;
    FC.FunctionFlags[F] := Flags;
    FC.FunctionModules[F] := Module;
    Inc(F);
  end;

begin
  { the static base URIs xml:base gives }
  for I := 0 to Integer(FModules.Count) - 1 do
  begin
    M := TModule(FModules[I]);
    for E := 0 to M.Tree.Count - 1 do
      if (M.Tree.Kind[E] = xnkElement) and HasXmlBase(M, E) then
      begin
        B := StaticBase(M, E);
        if (B <> M.Uri) and (FBaseUris.IndexOf(LandrixXmlUtf8ToKey(B)) < 0) then
          FBaseUris.Add(LandrixXmlUtf8ToKey(B));
      end;
  end;
  N := XfnFixedCount + XfnPerModule * (Integer(FModules.Count) + Integer(FBaseUris.Count)) +
    Integer(FC.UserFunctions.Count);
  SetLength(FC.FunctionUris, N);
  SetLength(FC.FunctionNames, N);
  SetLength(FC.FunctionArities, N);
  SetLength(FC.FunctionFlags, N);
  SetLength(FC.FunctionModules, N);
  F := 0;
  Add(XsltInternalNamespace, 'global', 1, [], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'current', 0, [xffVolatile], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'format-dateTime', 2, [], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'format-dateTime', 5, [], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'format-date', 2, [], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'format-date', 5, [], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'format-time', 2, [], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'format-time', 5, [], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'current-group', 0, [xffVolatile], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'current-grouping-key', 0, [xffVolatile], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'generate-id', 0, [xffFocus], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'generate-id', 1, [], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'key', 2, [xffFocus], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'key', 3, [], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'format-number', 2, [], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'format-number', 3, [], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'system-property', 1, [], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'function-available', 1, [], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'function-available', 2, [], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'element-available', 1, [], -1);
  Add(LandrixXmlXPathFunctionNamespace, 'regex-group', 1, [xffVolatile], -1);
  SetLength(FC.ModuleUris, Integer(FModules.Count) + Integer(FBaseUris.Count));
  for I := 0 to Integer(FModules.Count) - 1 do
  begin
    K := TModule(FModules[I]).Index;
    FC.ModuleUris[K] := TModule(FModules[I]).Uri;
  end;
  for I := 0 to Integer(FBaseUris.Count) - 1 do
    FC.ModuleUris[Integer(FModules.Count) + I] := LandrixXmlKeyToUtf8(FBaseUris[I]);
  for K := 0 to Integer(Length(FC.ModuleUris)) - 1 do
  begin
    Add(LandrixXmlXPathFunctionNamespace, 'doc', 1, [], K);
    Add(LandrixXmlXPathFunctionNamespace, 'doc-available', 1, [], K);
    Add(LandrixXmlXPathFunctionNamespace, 'document', 1, [], K);
    Add(LandrixXmlXPathFunctionNamespace, 'document', 2, [], K);
    Add(LandrixXmlXPathFunctionNamespace, 'static-base-uri', 0, [], K);
    Add(LandrixXmlXPathFunctionNamespace, 'resolve-uri', 1, [], K);
    Add(LandrixXmlXPathFunctionNamespace, 'unparsed-text', 1, [], K);
    Add(LandrixXmlXPathFunctionNamespace, 'unparsed-text', 2, [], K);
    Add(LandrixXmlXPathFunctionNamespace, 'unparsed-text-available', 1, [], K);
    Add(LandrixXmlXPathFunctionNamespace, 'unparsed-text-available', 2, [], K);
  end;
  { the stylesheet functions, in every module }
  FC.UserFunctionBase := F;
  for K := 0 to Integer(FC.UserFunctions.Count) - 1 do
  begin
    T := TXsltTemplate(FC.UserFunctions[K]);
    I := Pos8('}', T.Name);
    Add(Copy(T.Name, 2, I - 2), Copy(T.Name, I + 1, Length(T.Name) - I), Integer(T.Params.Count), [], -1);
  end;
end;

function TCompiler.Run(Tree: TLandrixXmlXPathTree; const BaseUri: TLandrixXmlUtf8): TXsltCompiled;
var
  Main: TModule;
  I, J: Integer;
  D: TDecl;
  L: TLandrixXmlUtf8;
begin
  FC := TXsltCompiled.Create;
  try
    { the fixed functions }
    Main := TModule.Create;
    Main.Tree := Tree;
    Main.Uri := BaseUri;
    Main.Index := 0;
    FModules.Add(Main);
    CheckRoot(Main);
    CheckModule(Main);
    Collect(Main);
    CollectFunctions;
    AddModuleFunctions;
    CompileGlobals;
    for I := 0 to Integer(FDecls.Count) - 1 do
    begin
      D := TDecl(FDecls[I]);
      if D.Simplified then
      begin
        CompileSimplified(D);
        Continue;
      end;
      if D.Module.Tree.NamespaceUriUtf8(D.Element) <> XsltNamespace then
        Continue;
      L := D.Module.Tree.LocalNameUtf8(D.Element);
      if L = 'template' then
        CompileTemplate(D)
      else if L = 'output' then
        CompileOutput(D)
      else if L = 'attribute-set' then
        CompileAttributeSet(D)
      else if L = 'character-map' then
        CompileCharacterMap(D)
      else if L = 'namespace-alias' then
        CompileNamespaceAlias(D)
      else if L = 'key' then
        CompileKey(D)
      else if L = 'decimal-format' then
        CompileDecimalFormat(D)
      else if (L = 'strip-space') or (L = 'preserve-space') then
        CompileSpace(D, L = 'strip-space')
      else if (L = 'variable') or (L = 'param') or (L = 'import') or (L = 'include') or
        (L = 'function') then
        { done }
      else if L = 'mode' then
        FModeDecls.Add(D)
      else if (L = 'import-schema') or (L = 'accumulator') or
        (L = 'use-package') or (L = 'global-context-item') then
        Unsupported(D.Module, D.Element, 'xsl:' + LandrixXmlUtf8ToString(L))
      else if IgnoredDeclaration(D.Module, D.Element) then
        { forwards compatible: ignored }
      else
        Fail(D.Module, D.Element, 'XTSE0010', 'unknown declaration xsl:' + LandrixXmlUtf8ToString(L));
    end;
    for I := 0 to Integer(FDupTemplates.Count) - 1 do
      if FC.NamedTemplates.Find(LandrixXmlUtf8ToKey(TXsltTemplate(FDupTemplates[I]).Name), J) and
        (TXsltTemplate(FC.NamedTemplates.Objects[J]).Precedence = TXsltTemplate(FDupTemplates[I]).Precedence) then
        Fail(TDecl(FDupTemplateDecls[I]).Module, TDecl(FDupTemplateDecls[I]).Element, 'XTSE0660',
          'two templates named ' + LandrixXmlUtf8ToString(TXsltTemplate(FDupTemplates[I]).Name));
    for I := 0 to Integer(FC.UserFunctions.Count) - 1 do
      CompileFunction(TXsltTemplate(FC.UserFunctions[I]), TDecl(FFunctionDecls[I]));
    for I := 0 to Integer(FOutputSeen.Count) - 1 do
      if TOutputSeen(FOutputSeen[I]).Conflict <> nil then
        Fail(TOutputSeen(FOutputSeen[I]).Conflict.Module, TOutputSeen(FOutputSeen[I]).Conflict.Element, 'XTSE1560',
          'two xsl:output declarations of one import precedence give different values of ' +
          LandrixXmlUtf8ToString(Copy(TOutputSeen(FOutputSeen[I]).Key,
          Pos8(' ', TOutputSeen(FOutputSeen[I]).Key) + 1, MaxInt)));
    CompileModes;
    { the initial mode when none is given }
    FC.DefaultMode := DefaultModeOf(Main, Main.Tree.DocumentElement);
    ModeOf(FC.DefaultMode);
    Finish;
    Result := FC;
    FC := nil;
  except
    FC.Free;
    FC := nil;
    raise;
  end;
end;

function XsltCompile(Tree: TLandrixXmlXPathTree; const BaseUri: TLandrixXmlUtf8;
  Resolver: TLandrixXmlXsltResolver): TObject;
var
  C: TCompiler;
begin
  C := TCompiler.Create(Resolver);
  try
    Result := C.Run(Tree, BaseUri);
  finally
    C.Free;
  end;
end;

end.
