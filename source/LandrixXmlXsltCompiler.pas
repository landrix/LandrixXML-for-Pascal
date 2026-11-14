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
  LandrixXmlXsltFormat;

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
  XfnFixedCount = 16;
  { then per module: doc#1, doc-available#1, document#1, document#2,
    static-base-uri#0, resolve-uri#1 (the module's URI is the static base
    URI) }
  XfnPerModule = 6;
  XfnDoc = 0;
  XfnDocAvailable = 1;
  XfnDocument = 2;
  XfnDocument2 = 3;
  XfnStaticBaseUri = 4;
  XfnResolveUri = 5;

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
    xskNumber, xskNamespace, xskForEachGroup);

  { a value with literal parts and expressions in curly brackets: Exprs[I] nil for a
    literal part }
  TXsltAvt = class
  public
    Parts: TLandrixXmlUtf8Array;
    Exprs: array of TLandrixXmlXPathExpression;
    function IsLiteral: Boolean;
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
    Select: TLandrixXmlXPathExpression;
    Body: TObjectList;
    HasAs: Boolean;
    AsType: TLandrixXmlXPathSequenceType;
    constructor Create;
    destructor Destroy; override;
  end;

  TXsltInstr = class
  public
    Kind: TXsltInstrKind;
    Module: TLandrixXmlUtf8;
    Line: Integer;
    Column: Integer;
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
    Template: TObject;
    { with-param (TXsltWithParam, owned) }
    Params: TObjectList;
    { xsl:variable, xsl:param of a template: the slot and name (Clark) }
    Slot: Integer;
    VarName: TLandrixXmlUtf8;
    IsParam: Boolean;
    Required: Boolean;
    HasAs: Boolean;
    AsType: TLandrixXmlXPathSequenceType;
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
    GroupingSeparator: TXsltAvt;
    GroupingSize: TXsltAvt;
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
  end;

  TXsltMode = class
  public
    Name: TLandrixXmlUtf8;
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
    Use: TLandrixXmlXPathExpression;
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
    Expressions: TObjectList;
    Output: TXsltOutputProperties;
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
    { decimal format name ('' the default) -> TXsltDecimalFormat, owned }
    DecimalFormats: TStringList;
    constructor Create;
    destructor Destroy; override;
    function FindMode(const Name: TLandrixXmlUtf8): TXsltMode;
    function FindGlobal(const Name: TLandrixXmlUtf8): TXsltGlobal;
  end;

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
  LandrixXmlReader;

{$IFDEF FPC}
function TXsltStringList.DoCompareText(const S1, S2: string): PtrInt;
{$ELSE}
function TXsltStringList.CompareStrings(const S1, S2: string): Integer;
{$ENDIF}
begin
  Result := CompareStr(S1, S2);
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

function XsltClarkOf(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlUtf8;
begin
  if NamespaceUri = '' then
    Result := LocalName
  else
    Result := '{' + NamespaceUri + '}' + LocalName;
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
  Branches.Free;
  Params.Free;
  Attributes.Free;
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
  Expressions := TObjectList.Create;
  Output := TXsltOutputProperties.Create;
  UserFunctions := TList.Create;
  Keys := TXsltStringList.Create;
  Keys.CaseSensitive := True;
  DecimalFormats := TXsltStringList.Create;
  DecimalFormats.CaseSensitive := True;
  DecimalFormats.AddObject('', TXsltDecimalFormat.Create);
end;

destructor TXsltCompiled.Destroy;
var
  I: Integer;
begin
  for I := 0 to Integer(Modes.Count) - 1 do
    Modes.Objects[I].Free;
  Modes.Free;
  NamedTemplates.Free;
  Rules.Free;
  Templates.Free;
  Globals.Free;
  Output.Free;
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
  if Modes.Find(LandrixXmlUtf8ToString(Name), I) then
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
    destructor Destroy; override;
    function IncludedAt(E: Integer): TModule;
  end;

  { a top-level declaration found in pass 1 }
  TDecl = class
  public
    Module: TModule;
    Element: Integer;
    Precedence: Integer;
    Order: Integer;
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
    FAllModeTemplates: TList;
    { the URIs of the modules being included or imported (a cycle) }
    FChain: TStringList;
    { the namespace URIs of variable names, with the prefix the static
      contexts bind them to }
    FVarUris: TStringList;
    FInternalCall: Boolean;
    function VarName(const Clark: TLandrixXmlUtf8): TLandrixXmlUtf8;
    procedure CheckStandard(M: TModule; E: Integer);
    procedure CheckModule(M: TModule);
    procedure LoadIncludes(M: TModule);
    procedure ProcessImports(M: TModule);
    procedure CollectDecls(M: TModule; Precedence: Integer);
    procedure AddModuleFunctions;
    procedure Fail(M: TModule; E: Integer; const Code, Msg: string);
    procedure Unsupported(M: TModule; E: Integer; const Msg: string);
    procedure XPathFailed(M: TModule; E: Integer; X: ELandrixXmlXPathError);
    function IsXsl(M: TModule; E: Integer; const Local: TLandrixXmlUtf8): Boolean;
    function Attr(M: TModule; E: Integer; const Local: TLandrixXmlUtf8; out Value: TLandrixXmlUtf8): Boolean;
    function ReqAttr(M: TModule; E: Integer; const Local: TLandrixXmlUtf8): TLandrixXmlUtf8;
    function QNameToClark(M: TModule; E: Integer; const QName: TLandrixXmlUtf8; UseDefault: Boolean): TLandrixXmlUtf8;
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
    procedure CompileWithParams(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
    function CompileVariable(M: TModule; E: Integer; Scope: TScope; Param: Boolean): TXsltInstr;
    procedure CompileGlobals;
    procedure CompileTemplate(D: TDecl);
    function PatternBranch(M: TModule; E: Integer; const Branch: TLandrixXmlUtf8; Scope: TScope;
      out Relative: Boolean): TLandrixXmlXPathExpression;
    procedure CompileNumber(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
    procedure CompileGroup(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
    procedure CompileKey(D: TDecl);
    procedure CompileDecimalFormat(D: TDecl);
    procedure CollectFunctions;
    procedure CompileFunction(T: TXsltTemplate; D: TDecl);
    procedure AddRules(D: TDecl; T: TXsltTemplate; const Match: TLandrixXmlUtf8; const Modes: TLandrixXmlUtf8);
    function ModeOf(const Name: TLandrixXmlUtf8): TXsltMode;
    procedure CompileOutput(D: TDecl);
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
  FChain := TXsltStringList.Create;
  FChain.CaseSensitive := True;
  FVarUris := TXsltStringList.Create;
  FVarUris.CaseSensitive := True;
end;

destructor TCompiler.Destroy;
begin
  FVarUris.Free;
  FChain.Free;
  FAllModeTemplates.Free;
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
    Line := M.Tree.Line[E];
    Column := M.Tree.Column[E];
  end;
  if M <> nil then
    raise ELandrixXmlXsltError.CreateXslt(xecXslt, Code, Msg, M.Uri, Line, Column)
  else
    raise ELandrixXmlXsltError.CreateXslt(xecXslt, Code, Msg, '', 0, 0);
end;

procedure TCompiler.Unsupported(M: TModule; E: Integer; const Msg: string);
begin
  raise ELandrixXmlXsltError.CreateXslt(xecUnsupported, 'FOER0000', Msg + ' is not supported', M.Uri,
    M.Tree.Line[E], M.Tree.Column[E]);
end;

{ an XPath error of an expression at E, as an XSLT error with E's position }
procedure TCompiler.XPathFailed(M: TModule; E: Integer; X: ELandrixXmlXPathError);
begin
  raise ELandrixXmlXsltError.CreateXslt(xecXPath, X.XPathCode, Copy(X.Message, Length(X.XPathCode) + 3, MaxInt),
    M.Uri, M.Tree.Line[E], M.Tree.Column[E]);
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

function TCompiler.QNameToClark(M: TModule; E: Integer; const QName: TLandrixXmlUtf8;
  UseDefault: Boolean): TLandrixXmlUtf8;
var
  I: Integer;
  Prefix, Local, Uri, Q: TLandrixXmlUtf8;
begin
  Q := Trim8(QName);
  I := Pos8(':', Q);
  if I > 0 then
  begin
    Prefix := Copy(Q, 1, I - 1);
    Local := Copy(Q, I + 1, Length(Q) - I);
    if not M.Tree.LookupNamespace(E, Prefix, Uri) then
      Fail(M, E, 'XTSE0280', 'the prefix ' + LandrixXmlUtf8ToString(Prefix) + ' is not declared');
  end
  else
  begin
    Local := Q;
    Uri := '';
    if UseDefault then
      M.Tree.LookupNamespace(E, '', Uri);
  end;
  if Local = '' then
    Fail(M, E, 'XTSE0020', 'not a QName: "' + LandrixXmlUtf8ToString(QName) + '"');
  Result := XsltClarkOf(Uri, Local);
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
  if not FResolver.Resolve(xrkStylesheet, M.Uri, Href, Uri, Content) then
    Fail(M, E, 'XTSE0165', 'the stylesheet module ' + LandrixXmlUtf8ToString(Href) + ' cannot be read');
  try
    { a cycle: the module is being included or imported already (the same
      module imported twice elsewhere is no cycle) }
    for I := 0 to Integer(FChain.Count) - 1 do
      if FChain[I] = LandrixXmlUtf8ToString(Uri) then
        Fail(M, E, 'XTSE0180', 'the module ' + LandrixXmlUtf8ToString(Uri) + ' includes or imports itself');
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
  E := Result.Tree.DocumentElement;
  if (E < 0) or not (IsXsl(Result, E, 'stylesheet') or IsXsl(Result, E, 'transform')) then
    Unsupported(Result, Result.Tree.FirstChild(0), 'a module that is no xsl:stylesheet (a simplified stylesheet)');
  CheckModule(Result);
end;

{ Reads the modules M includes, recursively (the chain: a cycle). }
procedure TCompiler.LoadIncludes(M: TModule);
var
  E, C, N: Integer;
  Inc: TModule;
begin
  FChain.Add(LandrixXmlUtf8ToString(M.Uri));
  try
    E := M.Tree.DocumentElement;
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
  FChain.Add(LandrixXmlUtf8ToString(M.Uri));
  try
    E := M.Tree.DocumentElement;
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
  P: Integer;
begin
  LoadIncludes(M);
  ProcessImports(M);
  P := FNextPrecedence;
  Inc(FNextPrecedence);
  CollectDecls(M, P);
end;

{ The attributes every XSLT element may have (an XSLT element: E, a
  literal result element: those in the XSLT namespace), rejected if they
  ask for what is not supported. }
procedure TCompiler.CheckStandard(M: TModule; E: Integer);
var
  I: Integer;
  L, V: TLandrixXmlUtf8;
  Xsl: Boolean;
begin
  Xsl := M.Tree.NamespaceUriUtf8(E) = XsltNamespace;
  for I := E + 1 to E + M.Tree.AttributeCount[E] do
  begin
    { xml:base would change the static base URI of the instructions in
      it (the module URI is taken for all of them) }
    if (M.Tree.NamespaceUriUtf8(I) = LandrixXmlNamespaceXml) and (M.Tree.LocalNameUtf8(I) = 'base') then
      Unsupported(M, E, 'xml:base in a stylesheet');
    if Xsl then
    begin
      if M.Tree.NamespaceUriUtf8(I) = XsltNamespace then
        Fail(M, E, 'XTSE0090', 'an XSLT element has no attribute in the XSLT namespace (' +
          LandrixXmlUtf8ToString(M.Tree.PrefixUtf8(I)) + ':' + LandrixXmlUtf8ToString(M.Tree.LocalNameUtf8(I)) + ')');
      if M.Tree.NamespaceUriUtf8(I) <> '' then
        Continue;
    end
    else if M.Tree.NamespaceUriUtf8(I) <> XsltNamespace then
      Continue;
    L := M.Tree.LocalNameUtf8(I);
    V := Trim8(M.Tree.ValueUtf8(I));
    if (L = 'use-when') or (L = 'xpath-default-namespace') or (L = 'default-collation') or
      (L = 'default-mode') or (L = 'default-validation') or (L = 'input-type-annotations') or
      ((L = 'expand-text') and (V = 'yes')) or ((L = 'inherit-namespaces') and (V = 'no')) or
      ((L = 'extension-element-prefixes') and (V <> '')) or
      ((L = 'validation') and (V <> 'strip') and (V <> 'preserve')) or (L = 'type') then
      Unsupported(M, E, LandrixXmlUtf8ToString(L) + '="' + LandrixXmlUtf8ToString(V) + '"');
    if (L = 'version') and (V <> '2.0') and (V <> '3.0') and not (Xsl and IsXsl(M, E, 'output')) then
      Unsupported(M, E, 'version="' + LandrixXmlUtf8ToString(V) + '" (only 2.0 is processed as such)');
  end;
end;

{ CheckStandard for every element of a module (also those the compiler
  never looks at as instructions, such as xsl:when or xsl:param) }
procedure TCompiler.CheckModule(M: TModule);
var
  I: Integer;
begin
  for I := 0 to M.Tree.Count - 1 do
    if M.Tree.Kind[I] = xnkElement then
      CheckStandard(M, I);
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
  I := FVarUris.IndexOf(LandrixXmlUtf8ToString(Uri));
  if I < 0 then
    I := FVarUris.Add(LandrixXmlUtf8ToString(Uri));
  Result := '#v' + LandrixXmlStringToUtf8(IntToStr(I)) + ':' + Local;
end;

function TCompiler.NewContext(M: TModule; E: Integer; Scope: TScope): TLandrixXmlXPathStaticContext;
var
  Prefixes, Names: TLandrixXmlUtf8Array;
  Uri: TLandrixXmlUtf8;
  I, J, N, K: Integer;
  G: TXsltGlobal;
begin
  Names := nil;
  Result := TLandrixXmlXPathStaticContext.Create;
  try
    Result.Profile := xppSaxon;
    Prefixes := M.Tree.InScopePrefixesUtf8(E);
    for I := 0 to Integer(Length(Prefixes)) - 1 do
      if (Prefixes[I] <> '') and (Prefixes[I] <> 'xml') and M.Tree.LookupNamespace(E, Prefixes[I], Uri) then
        Result.AddNamespace(Prefixes[I], Uri);
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
        LandrixXmlStringToUtf8(FVarUris[I]));
    for I := 0 to N - 1 do
      Result.DeclareVariable(Names[I]);
    { the functions; those of a module (doc(), document()) under their
      own names for the expressions of that module only }
    for I := 0 to Integer(Length(FC.FunctionNames)) - 1 do
    begin
      if (I = XfnGlobal) and not FInternalCall then
        { out of reach of the stylesheet's expressions }
        K := Result.DeclareFunction(XsltInternalNamespace, '#global', FC.FunctionArities[I])
      else if (FC.FunctionModules[I] >= 0) and (FC.FunctionModules[I] <> M.Index) then
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

function TCompiler.CompileAvt(M: TModule; E: Integer; const Text: TLandrixXmlUtf8; Scope: TScope): TXsltAvt;
var
  I, Start, Depth, N: Integer;
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
        else if Text[I] = '{' then
          Inc(Depth)
        else if Text[I] = '}' then
          Dec(Depth);
        Inc(I);
      end;
      if I > Length(Text) then
        Fail(M, E, 'XTSE0350', 'an attribute value template without "}"');
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
          Copy(X.Message, Length(X.XPathCode) + 3, MaxInt), M.Uri, M.Tree.Line[E], M.Tree.Column[E]);
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
  Result.Line := M.Tree.Line[E];
  Result.Column := M.Tree.Column[E];
end;

{ xml:space="preserve" on the node or an ancestor (nearest wins) }
function PreservesSpace(T: TLandrixXmlXPathTree; N: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
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
  C, SavedCount: Integer;
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
          S := M.Tree.ValueUtf8(C);
          if (Trim8(S) <> '') or PreservesSpace(M.Tree, C) then
          begin
            I := NewInstr(xskText, M, C);
            I.Text := S;
            Body.Add(I);
          end;
        end;
      xnkElement:
        begin
          if IsXsl(M, C, '') then
            I := CompileInstr(M, C, Scope)
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
  the XSLT namespace, xml and the excluded prefixes of E, its literal
  ancestors (xsl:exclude-result-prefixes) and the xsl:stylesheet element
  (exclude-result-prefixes). }
procedure LiteralNamespaces(M: TModule; E: Integer; Instr: TXsltInstr);
var
  Prefixes, Excluded: TLandrixXmlUtf8Array;
  Uri, V, P: TLandrixXmlUtf8;
  I, J, N, A, Count: Integer;
  Skip, All: Boolean;

  procedure AddExcluded(Element: Integer; Stylesheet: Boolean);
  var
    K, Start: Integer;
    W: TLandrixXmlUtf8;
  begin
    V := '';
    for K := Element + 1 to Element + M.Tree.AttributeCount[Element] do
      if (M.Tree.LocalNameUtf8(K) = 'exclude-result-prefixes') and
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
        if W = '#all' then
          All := True
        else
        begin
          if W = '#default' then
            W := '';
          SetLength(Excluded, Length(Excluded) + 1);
          Excluded[High(Excluded)] := W;
        end;
      end;
  end;

begin
  Excluded := nil;
  All := False;
  N := E;
  while N >= 0 do
  begin
    if M.Tree.Kind[N] = xnkElement then
    begin
      if M.Tree.NamespaceUriUtf8(N) = XsltNamespace then
      begin
        if (M.Tree.Parent[N] >= 0) and (M.Tree.Kind[M.Tree.Parent[N]] = xnkDocument) then
          AddExcluded(N, True);
      end
      else
        AddExcluded(N, False);
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
    if (P = 'xml') or not M.Tree.LookupNamespace(E, P, Uri) or (Uri = XsltNamespace) then
      Continue;
    Skip := False;
    { the element's own namespace and those of its attributes stay }
    if All or (Length(Excluded) > 0) then
    begin
      for J := 0 to Integer(Length(Excluded)) - 1 do
        if Excluded[J] = P then
          Skip := True;
      if All then
        Skip := True;
      if Skip then
      begin
        if (M.Tree.PrefixUtf8(E) = P) then
          Skip := False;
        for A := E + 1 to E + M.Tree.AttributeCount[E] do
          if (P <> '') and (M.Tree.PrefixUtf8(A) = P) then
            Skip := False;
      end;
    end;
    if Skip then
      Continue;
    Instr.NsPrefixes[Count] := P;
    Instr.NsUris[Count] := Uri;
    Inc(Count);
  end;
  SetLength(Instr.NsPrefixes, Count);
  SetLength(Instr.NsUris, Count);
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
          Unsupported(M, E, 'xsl:use-attribute-sets');
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

procedure TCompiler.CompileWithParams(M: TModule; E: Integer; Scope: TScope; Instr: TXsltInstr);
var
  C: Integer;
  P: TXsltWithParam;
  V: TLandrixXmlUtf8;
begin
  C := M.Tree.FirstChild(E);
  while C >= 0 do
  begin
    if IsXsl(M, C, 'with-param') then
    begin
      P := TXsltWithParam.Create;
      Instr.Params.Add(P);
      P.Name := QNameToClark(M, C, ReqAttr(M, C, 'name'), False);
      if Attr(M, C, 'tunnel', V) and (V = 'yes') then
        Unsupported(M, C, 'a tunnel parameter');
      P.Select := CompileAttr(M, C, 'select', Scope);
      P.HasAs := ParseType(M, C, Scope, P.AsType);
      if P.Select = nil then
        CompileBody(M, C, Scope, P.Body, -1);
    end
    else if IsXsl(M, C, 'sort') then
      Unsupported(M, C, 'xsl:sort')
    else if (M.Tree.Kind[C] = xnkElement) or
      ((M.Tree.Kind[C] = xnkText) and (Trim8(M.Tree.ValueUtf8(C)) <> '')) then
      Fail(M, C, 'XTSE0010', 'only xsl:with-param is allowed here');
    C := M.Tree.NextSibling[C];
  end;
end;

function TCompiler.CompileVariable(M: TModule; E: Integer; Scope: TScope; Param: Boolean): TXsltInstr;
var
  Lexical, V: TLandrixXmlUtf8;
begin
  Result := NewInstr(xskVariable, M, E);
  try
    Result.IsParam := Param;
    Lexical := Trim8(ReqAttr(M, E, 'name'));
    Result.VarName := QNameToClark(M, E, Lexical, False);
    if Param then
    begin
      Result.Required := Attr(M, E, 'required', V) and (V = 'yes');
      if Attr(M, E, 'tunnel', V) and (V = 'yes') then
        Unsupported(M, E, 'a tunnel parameter');
    end;
    Result.Select := CompileAttr(M, E, 'select', Scope);
    Result.HasAs := ParseType(M, E, Scope, Result.AsType);
    if Result.Select = nil then
      CompileBody(M, E, Scope, Result.Body, -1);
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
  { wherever it is (for-each, apply-templates or a wrong place) }
  if L = 'sort' then
    Unsupported(M, E, 'xsl:sort');
  if L = 'fallback' then
    Exit;
  if (L = 'apply-imports') or (L = 'next-match') or (L = 'analyze-string') or
    (L = 'result-document') or (L = 'perform-sort') or (L = 'namespace') or (L = 'try') or
    (L = 'iterate') or (L = 'evaluate') or (L = 'where-populated') or (L = 'on-empty') or
    (L = 'on-non-empty') or (L = 'map') or (L = 'array') or (L = 'merge') or (L = 'fork') or
    (L = 'assert') or (L = 'break') or (L = 'next-iteration') or (L = 'source-document') or
    (L = 'call-function') or (L = 'context-item') then
    Unsupported(M, E, 'xsl:' + LandrixXmlUtf8ToString(L));
  try
    if L = 'text' then
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
      if Attr(M, E, 'disable-output-escaping', V) and (V = 'yes') then
        Unsupported(M, E, 'disable-output-escaping');
    end
    else if L = 'value-of' then
    begin
      Result := NewInstr(xskValueOf, M, E);
      Result.Select := CompileAttr(M, E, 'select', Scope);
      if Attr(M, E, 'separator', V) then
        Result.Separator := CompileAvt(M, E, V, Scope);
      if Attr(M, E, 'disable-output-escaping', V) and (V = 'yes') then
        Unsupported(M, E, 'disable-output-escaping');
      if Result.Select = nil then
        CompileBody(M, E, Scope, Result.Body, -1);
    end
    else if L = 'apply-templates' then
    begin
      Result := NewInstr(xskApplyTemplates, M, E);
      if Attr(M, E, 'select', V) then
        Result.Select := Compile(M, E, V, Scope)
      else
        Result.Select := Compile(M, E, 'child::node()', Scope);
      V := '';
      Attr(M, E, 'mode', V);
      V := Trim8(V);
      if V = '#current' then
        Result.CurrentMode := True
      else if (V = '') or (V = '#default') then
        Result.Mode := ModeOf('')
      else
        Result.Mode := ModeOf(QNameToClark(M, E, V, False));
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
      CompileBody(M, E, Scope, Result.Body, -1);
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
    end
    else if L = 'copy-of' then
    begin
      Result := NewInstr(xskCopyOf, M, E);
      Result.Select := Compile(M, E, ReqAttr(M, E, 'select'), Scope);
      if Attr(M, E, 'copy-namespaces', V) and (V = 'no') then
        Unsupported(M, E, 'copy-namespaces="no"');
    end
    else if L = 'copy' then
    begin
      Result := NewInstr(xskCopy, M, E);
      if Attr(M, E, 'copy-namespaces', V) and (V = 'no') then
        Unsupported(M, E, 'copy-namespaces="no"');
      if Attr(M, E, 'use-attribute-sets', V) then
        Unsupported(M, E, 'use-attribute-sets');
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
        Unsupported(M, E, 'use-attribute-sets');
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
        CompileBody(M, E, Scope, Result.Body, -1);
    end
    else if L = 'comment' then
    begin
      Result := NewInstr(xskComment, M, E);
      Result.Select := CompileAttr(M, E, 'select', Scope);
      if Result.Select = nil then
        CompileBody(M, E, Scope, Result.Body, -1);
    end
    else if L = 'processing-instruction' then
    begin
      Result := NewInstr(xskProcessingInstruction, M, E);
      Result.NameAvt := CompileAvt(M, E, ReqAttr(M, E, 'name'), Scope);
      Result.Select := CompileAttr(M, E, 'select', Scope);
      if Result.Select = nil then
        CompileBody(M, E, Scope, Result.Body, -1);
    end
    else if L = 'message' then
    begin
      Result := NewInstr(xskMessage, M, E);
      if Attr(M, E, 'terminate', V) then
        Result.NameAvt := CompileAvt(M, E, V, Scope);
      Result.Select := CompileAttr(M, E, 'select', Scope);
      CompileBody(M, E, Scope, Result.Body, -1);
    end
    else if L = 'document' then
    begin
      Result := NewInstr(xskDocument, M, E);
      CompileBody(M, E, Scope, Result.Body, -1);
    end
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
  FC.Modes.AddObject(LandrixXmlUtf8ToString(Name), Result);
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
  Decls: TList;
begin
  { the declaration of each name with the highest precedence }
  Names := TXsltStringList.Create;
  Decls := TList.Create;
  try
    for I := 0 to Integer(FDecls.Count) - 1 do
    begin
      D := TDecl(FDecls[I]);
      if not (IsXsl(D.Module, D.Element, 'variable') or IsXsl(D.Module, D.Element, 'param')) then
        Continue;
      Name := QNameToClark(D.Module, D.Element, ReqAttr(D.Module, D.Element, 'name'), False);
      Found := False;
      for J := 0 to Integer(Names.Count) - 1 do
        if Names[J] = LandrixXmlUtf8ToString(Name) then
        begin
          Found := True;
          Best := TDecl(Decls[J]);
          if Best.Precedence = D.Precedence then
            Fail(D.Module, D.Element, 'XTSE0630', 'the global variable ' + LandrixXmlUtf8ToString(Name) +
              ' is declared twice');
          if D.Precedence > Best.Precedence then
            Decls[J] := D;
        end;
      if not Found then
      begin
        Names.Add(LandrixXmlUtf8ToString(Name));
        Decls.Add(D);
      end;
    end;
    for I := 0 to Integer(Decls.Count) - 1 do
    begin
      D := TDecl(Decls[I]);
      G := TXsltGlobal.Create;
      FC.Globals.Add(G);
      G.Name := LandrixXmlStringToUtf8(Names[I]);
      Lexical := Trim8(ReqAttr(D.Module, D.Element, 'name'));
      G.Lexical := Lexical;
      G.Module := D.Module.Uri;
      G.Line := D.Module.Tree.Line[D.Element];
      G.Column := D.Module.Tree.Column[D.Element];
      G.Slot := I;
      G.Precedence := D.Precedence;
      G.IsParam := IsXsl(D.Module, D.Element, 'param');
      G.Required := G.IsParam and Attr(D.Module, D.Element, 'required', V) and (V = 'yes');
      if Attr(D.Module, D.Element, 'tunnel', V) and (V = 'yes') then
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
          CompileBody(D.Module, D.Element, Scope, G.Body, -1);
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
  I: Integer;
  Quote: AnsiChar;
begin
  Result := '';
  Quote := #0;
  for I := 1 to Length(S) do
  begin
    if Quote <> #0 then
    begin
      if S[I] = Quote then
        Quote := #0;
    end
    else if S[I] in ['''', '"'] then
      Quote := S[I]
    else if S[I] in [#9, #10, #13, ' '] then
      Continue;
    Result := Result + Copy(S, I, 1);
  end;
end;

{ the default priority of a pattern branch (XSLT 2.0, 6.4) }
function DefaultPriority(const Branch: TLandrixXmlUtf8): Double;
var
  S, Test: TLandrixXmlUtf8;
  I: Integer;

  function IsNCName(const N: TLandrixXmlUtf8): Boolean;
  var
    K: Integer;
  begin
    Result := N <> '';
    for K := 1 to Length(N) do
      if not ((N[K] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.']) or (Ord(N[K]) >= 128)) then
        Result := False;
    if Result and (N[1] in ['0'..'9', '-', '.']) then
      Result := False;
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
  I, Start, Depth: Integer;
  Quote: AnsiChar;
begin
  Result := nil;
  Depth := 0;
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
        Key := 'e' + LandrixXmlUtf8ToString(XsltClarkOf(N.NamespaceUri, N.LocalName))
      else if N.Axis = xaxAttribute then
        Key := 'a' + LandrixXmlUtf8ToString(XsltClarkOf(N.NamespaceUri, N.LocalName));
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

{ A branch of a pattern as the expression MatchesPattern takes: "//"
  before a relative path (Relative), rooted ones as they are,
  document-node(...) as the root tested. }
function TCompiler.PatternBranch(M: TModule; E: Integer; const Branch: TLandrixXmlUtf8; Scope: TScope;
  out Relative: Boolean): TLandrixXmlXPathExpression;
var
  B, Text: TLandrixXmlUtf8;
begin
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
end;

{ xsl:number (XSLT 2.0 12): value or the place of the selected node
  (level, count, from), the format and the grouping as templates; lang,
  letter-value and ordinal are not supported. }
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
        (V <> 'grouping-separator') and (V <> 'grouping-size') and (V <> 'start-at') and (V <> 'version') then
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
  if Attr(M, E, 'lang', V) or Attr(M, E, 'letter-value', V) or Attr(M, E, 'ordinal', V) then
    Unsupported(M, E, 'xsl:number with lang, letter-value or ordinal');
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
  I, Count: Integer;
begin
  Branches := nil;
  if Attr(M, E, 'collation', V) and (Trim8(V) <> 'http://www.w3.org/2005/xpath-functions/collation/codepoint') then
    Unsupported(M, E, 'a collation other than the codepoint collation');
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
  if Instr.GroupKind >= 2 then
  begin
    if Attr(M, E, 'collation', V) then
      Fail(M, E, 'XTSE1090', 'collation only with group-by or group-adjacent');
    Branches := SplitPattern(Pattern);
    SetLength(Instr.CountPatterns, Length(Branches));
    SetLength(Instr.CountRelative, Length(Branches));
    for I := 0 to Integer(Length(Branches)) - 1 do
    begin
      if Branches[I] = '' then
        Fail(M, E, 'XTSE0340', 'an empty pattern');
      Instr.CountPatterns[I] := PatternBranch(M, E, Branches[I], Scope, Instr.CountRelative[I]);
    end;
  end;
  CompileBody(M, E, Scope, Instr.Body, -1);
end;

{ xsl:key: the declarations of one name are combined (all precedences);
  a name with a prefix is not supported (key() gets the name as a string
  and resolves no prefixes). }
procedure TCompiler.CompileKey(D: TDecl);
var
  M: TModule;
  E, I: Integer;
  Name, V: TLandrixXmlUtf8;
  Branches: TLandrixXmlUtf8Array;
  K: TXsltKey;
  Decl: TXsltKeyDecl;
begin
  M := D.Module;
  E := D.Element;
  Branches := nil;
  V := Trim8(ReqAttr(M, E, 'name'));
  if Pos8(':', V) > 0 then
    Unsupported(M, E, 'a key name with a prefix');
  Name := QNameToClark(M, E, V, False);
  if Attr(M, E, 'collation', V) and (Trim8(V) <> 'http://www.w3.org/2005/xpath-functions/collation/codepoint') then
    Unsupported(M, E, 'a collation other than the codepoint collation');
  if not Attr(M, E, 'use', V) then
    Unsupported(M, E, 'xsl:key without use (a sequence constructor)');
  I := M.Tree.FirstChild(E);
  while I >= 0 do
  begin
    if (M.Tree.Kind[I] = xnkElement) or (M.Tree.Kind[I] = xnkText) and (Trim8(M.Tree.ValueUtf8(I)) <> '') then
      Fail(M, E, 'XTSE1205', 'xsl:key has use and content');
    I := M.Tree.NextSibling[I];
  end;
  I := FC.Keys.IndexOf(LandrixXmlUtf8ToString(Name));
  if I >= 0 then
    K := TXsltKey(FC.Keys.Objects[I])
  else
  begin
    K := TXsltKey.Create;
    K.Name := Name;
    K.Index := Integer(FC.Keys.Count);
    FC.Keys.AddObject(LandrixXmlUtf8ToString(Name), K);
  end;
  Decl := TXsltKeyDecl.Create;
  K.Decls.Add(Decl);
  Decl.Use := Compile(M, E, V, nil);
  Branches := SplitPattern(ReqAttr(M, E, 'match'));
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
{ an NCName (non-ASCII characters taken as name characters) }
function NameOk(const N: TLandrixXmlUtf8): Boolean;
var
  K: Integer;
begin
  Result := (N <> '') and not (N[1] in ['0'..'9', '-', '.']);
  for K := 1 to Length(N) do
    if not ((N[K] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.']) or (Ord(N[K]) >= 128)) then
      Result := False;
end;

procedure TCompiler.CompileDecimalFormat(D: TDecl);
var
  M: TModule;
  E, I, J, K: Integer;
  Name, L, V: TLandrixXmlUtf8;
  F: TXsltDecimalFormat;

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
    if not NameOk(V) then
      Fail(M, E, 'XTSE0020', 'not a decimal format name: "' + LandrixXmlUtf8ToString(V) + '"');
    Name := V;
  end;
  K := FC.DecimalFormats.IndexOf(LandrixXmlUtf8ToString(Name));
  if K >= 0 then
    F := TXsltDecimalFormat(FC.DecimalFormats.Objects[K])
  else
  begin
    F := TXsltDecimalFormat.Create;
    FC.DecimalFormats.AddObject(LandrixXmlUtf8ToString(Name), F);
  end;
  for I := E + 1 to E + M.Tree.AttributeCount[E] do
  begin
    if M.Tree.NamespaceUriUtf8(I) <> '' then
      Continue;
    L := M.Tree.LocalNameUtf8(I);
    V := M.Tree.ValueUtf8(I);
    if (L = 'name') or (L = 'infinity') or (L = 'NaN') then
      { strings }
    else if (L = 'decimal-separator') or (L = 'grouping-separator') or (L = 'minus-sign') or (L = 'percent') or
      (L = 'per-mille') or (L = 'zero-digit') or (L = 'digit') or (L = 'pattern-separator') then
    begin
      if CharCount(V) <> 1 then
        Fail(M, E, 'XTSE0020', 'xsl:decimal-format ' + LandrixXmlUtf8ToString(L) + ' must be one character');
    end
    else
      Fail(M, E, 'XTSE0090', 'xsl:decimal-format has no attribute ' + LandrixXmlUtf8ToString(L));
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

procedure TCompiler.AddRules(D: TDecl; T: TXsltTemplate; const Match: TLandrixXmlUtf8; const Modes: TLandrixXmlUtf8);
var
  Branches: TLandrixXmlUtf8Array;
  ModeNames: TList;
  I, J, Start: Integer;
  R: TXsltRule;
  B, V, W: TLandrixXmlUtf8;
  Prio: Double;
  HasPrio, All: Boolean;
  Code: Integer;
begin
  HasPrio := Attr(D.Module, D.Element, 'priority', V);
  Prio := 0;
  if HasPrio then
  begin
    Val(LandrixXmlUtf8ToString(Trim8(V)), Prio, Code);
    if not IsDecimal(Trim8(V)) then
      Code := 1;
    if Code <> 0 then
      Fail(D.Module, D.Element, 'XTSE0530', 'the priority "' + LandrixXmlUtf8ToString(V) + '" is not a number');
  end;
  ModeNames := TList.Create;
  try
    All := False;
    W := Modes + ' ';
    Start := 1;
    for I := 1 to Length(W) do
      if W[I] in [#9, #10, #13, ' '] then
      begin
        B := Copy(W, Start, I - Start);
        Start := I + 1;
        if B = '' then
          Continue;
        if B = '#all' then
          All := True
        else if B = '#default' then
          ModeNames.Add(ModeOf(''))
        else
          ModeNames.Add(ModeOf(QNameToClark(D.Module, D.Element, B, False)));
      end;
    if Trim8(Modes) = '' then
      ModeNames.Add(ModeOf(''));
    Branches := SplitPattern(Match);
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
      if (Uri = XsltNamespace) or (Uri = LandrixXmlXPathFunctionNamespace) or
        (Uri = 'http://www.w3.org/2001/XMLSchema') or (Uri = 'http://www.w3.org/2001/XMLSchema-instance') or
        (Uri = LandrixXmlNamespaceXml) then
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
      K := Keys.IndexOf(LandrixXmlUtf8ToString(Key));
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
        T.Line := M.Tree.Line[D.Element];
        T.Column := M.Tree.Column[D.Element];
        Continue;
      end;
      T := TXsltTemplate.Create;
      FC.Templates.Add(T);
      T.Name := Name;
      T.Module := M.Uri;
      T.Line := M.Tree.Line[D.Element];
      T.Column := M.Tree.Column[D.Element];
      T.Precedence := D.Precedence;
      { the parameters, to count them (CompileFunction compiles them) }
      for C := 1 to Arity do
        T.Params.Add(nil);
      FC.UserFunctions.Add(T);
      FFunctionDecls.Add(D);
      Keys.AddObject(LandrixXmlUtf8ToString(Key), T);
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
begin
  M := D.Module;
  E := D.Element;
  T := TXsltTemplate.Create;
  FC.Templates.Add(T);
  T.Module := M.Uri;
  T.Line := M.Tree.Line[E];
  T.Column := M.Tree.Column[E];
  T.Precedence := D.Precedence;
  if Attr(M, E, 'name', V) then
    T.Name := QNameToClark(M, E, V, False);
  Match := '';
  if not Attr(M, E, 'match', Match) and (T.Name = '') then
    Fail(M, E, 'XTSE0500', 'xsl:template needs a match or name attribute');
  Modes := '';
  if Attr(M, E, 'mode', Modes) and (Match = '') then
    Fail(M, E, 'XTSE0500', 'xsl:template with a mode needs a match attribute');
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
  if Match <> '' then
    AddRules(D, T, Match, Modes);
  if T.Name <> '' then
  begin
    if FC.NamedTemplates.Find(LandrixXmlUtf8ToString(T.Name), I) then
    begin
      if TXsltTemplate(FC.NamedTemplates.Objects[I]).Precedence = T.Precedence then
        Fail(M, E, 'XTSE0660', 'two templates named ' + LandrixXmlUtf8ToString(T.Name));
      if TXsltTemplate(FC.NamedTemplates.Objects[I]).Precedence < T.Precedence then
        FC.NamedTemplates.Objects[I] := T;
    end
    else
      FC.NamedTemplates.AddObject(LandrixXmlUtf8ToString(T.Name), T);
  end;
end;

procedure TCompiler.CompileOutput(D: TDecl);
var
  I: Integer;
  M: TModule;
  L, V: TLandrixXmlUtf8;
begin
  M := D.Module;
  for I := D.Element + 1 to D.Element + M.Tree.AttributeCount[D.Element] do
  begin
    if M.Tree.NamespaceUriUtf8(I) <> '' then
      Continue;
    L := M.Tree.LocalNameUtf8(I);
    { standard attributes (CheckStandard) }
    if (L = 'exclude-result-prefixes') or (L = 'extension-element-prefixes') or (L = 'expand-text') then
      Continue;
    if L = 'name' then
      Unsupported(M, D.Element, 'a named xsl:output');
    V := Trim8(M.Tree.ValueUtf8(I));
    case XsltOutputPropertyStatus(L, V) of
      xosUnsupported:
        Unsupported(M, D.Element, 'xsl:output ' + LandrixXmlUtf8ToString(L) + '="' + LandrixXmlUtf8ToString(V) + '"');
      xosUnknown:
        Fail(M, D.Element, 'XTSE0090', 'xsl:output has no attribute ' + LandrixXmlUtf8ToString(L));
    else
      { supported }
    end;
    FC.Output.SetValue(L, V);
  end;
end;

{ Call targets, modes for #all, rule order. }
procedure TCompiler.Finish;
var
  I, J, K: Integer;
  Mode: TXsltMode;

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
      if not P.Required then
        Continue;
      Found := False;
      for B := 0 to Integer(Instr.Params.Count) - 1 do
        if TXsltWithParam(Instr.Params[B]).Name = P.VarName then
          Found := True;
      if not Found then
        raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTSE0690', 'the required parameter ' +
          LandrixXmlUtf8ToString(P.VarName) + ' is not supplied', Instr.Module, Instr.Line, Instr.Column);
    end;
    for B := 0 to Integer(Instr.Params.Count) - 1 do
    begin
      Found := False;
      for A := 0 to Integer(TXsltTemplate(Instr.Template).Params.Count) - 1 do
        if TXsltInstr(TXsltTemplate(Instr.Template).Params[A]).VarName = TXsltWithParam(Instr.Params[B]).Name then
          Found := True;
      if not Found then
        raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTSE0680', 'the template ' +
          LandrixXmlUtf8ToString(TXsltTemplate(Instr.Template).Name) + ' has no parameter ' +
          LandrixXmlUtf8ToString(TXsltWithParam(Instr.Params[B]).Name), Instr.Module, Instr.Line, Instr.Column);
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
      if Instr.Kind = xskCallTemplate then
      begin
        if not FC.NamedTemplates.Find(LandrixXmlUtf8ToString(Instr.VarName), P) then
          raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTSE0650', 'no template named ' +
            LandrixXmlUtf8ToString(Instr.VarName), Instr.Module, Instr.Line, Instr.Column);
        Instr.Template := FC.NamedTemplates.Objects[P];
        CheckRequired(Instr);
      end;
      Resolve(Instr.Body);
      for P := 0 to Integer(Instr.Branches.Count) - 1 do
        Resolve(TXsltInstr(Instr.Branches[P]).Body);
      for P := 0 to Integer(Instr.Params.Count) - 1 do
        Resolve(TXsltWithParam(Instr.Params[P]).Body);
    end;
  end;

begin
  for I := 0 to Integer(FC.Templates.Count) - 1 do
  begin
    Resolve(TXsltTemplate(FC.Templates[I]).Body);
    for J := 0 to Integer(TXsltTemplate(FC.Templates[I]).Params.Count) - 1 do
      Resolve(TXsltInstr(TXsltTemplate(FC.Templates[I]).Params[J]).Body);
  end;
  for I := 0 to Integer(FC.Globals.Count) - 1 do
    Resolve(TXsltGlobal(FC.Globals[I]).Body);
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
  N, I, K, F: Integer;
  T: TXsltTemplate;

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
  N := XfnFixedCount + XfnPerModule * Integer(FModules.Count) + Integer(FC.UserFunctions.Count);
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
  SetLength(FC.ModuleUris, FModules.Count);
  for I := 0 to Integer(FModules.Count) - 1 do
  begin
    K := TModule(FModules[I]).Index;
    FC.ModuleUris[K] := TModule(FModules[I]).Uri;
  end;
  for K := 0 to Integer(FModules.Count) - 1 do
  begin
    Add(LandrixXmlXPathFunctionNamespace, 'doc', 1, [], K);
    Add(LandrixXmlXPathFunctionNamespace, 'doc-available', 1, [], K);
    Add(LandrixXmlXPathFunctionNamespace, 'document', 1, [], K);
    Add(LandrixXmlXPathFunctionNamespace, 'document', 2, [], K);
    Add(LandrixXmlXPathFunctionNamespace, 'static-base-uri', 0, [], K);
    Add(LandrixXmlXPathFunctionNamespace, 'resolve-uri', 1, [], K);
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
  E, I: Integer;
  D: TDecl;
  L, V: TLandrixXmlUtf8;
begin
  FC := TXsltCompiled.Create;
  try
    { the fixed functions }
    Main := TModule.Create;
    Main.Tree := Tree;
    Main.Uri := BaseUri;
    Main.Index := 0;
    FModules.Add(Main);
    E := Tree.DocumentElement;
    if (E < 0) or not (IsXsl(Main, E, 'stylesheet') or IsXsl(Main, E, 'transform')) then
    begin
      if E >= 0 then
        Unsupported(Main, E, 'a simplified stylesheet (literal result element as the stylesheet)');
      Fail(Main, -1, 'XTSE0150', 'the stylesheet has no element');
    end;
    if not Attr(Main, E, 'version', V) then
      Fail(Main, E, 'XTSE0010', 'xsl:stylesheet needs a version attribute');
    if Trim8(V) = '1.0' then
      Unsupported(Main, E, 'an XSLT 1.0 stylesheet (backwards compatible processing)');
    CheckModule(Main);
    Collect(Main);
    CollectFunctions;
    AddModuleFunctions;
    CompileGlobals;
    for I := 0 to Integer(FDecls.Count) - 1 do
    begin
      D := TDecl(FDecls[I]);
      if D.Module.Tree.NamespaceUriUtf8(D.Element) <> XsltNamespace then
        Continue;
      L := D.Module.Tree.LocalNameUtf8(D.Element);
      if L = 'template' then
        CompileTemplate(D)
      else if L = 'output' then
        CompileOutput(D)
      else if L = 'key' then
        CompileKey(D)
      else if L = 'decimal-format' then
        CompileDecimalFormat(D)
      else if (L = 'variable') or (L = 'param') or (L = 'import') or (L = 'include') or
        (L = 'function') then
        { done }
      else if (L = 'strip-space') or
        (L = 'preserve-space') or (L = 'attribute-set') or (L = 'namespace-alias') or
        (L = 'character-map') or (L = 'import-schema') or (L = 'mode') or (L = 'accumulator') or
        (L = 'use-package') or (L = 'global-context-item') then
        Unsupported(D.Module, D.Element, 'xsl:' + LandrixXmlUtf8ToString(L))
      else
        Fail(D.Module, D.Element, 'XTSE0010', 'unknown declaration xsl:' + LandrixXmlUtf8ToString(L));
    end;
    for I := 0 to Integer(FC.UserFunctions.Count) - 1 do
      CompileFunction(TXsltTemplate(FC.UserFunctions[I]), TDecl(FFunctionDecls[I]));
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
