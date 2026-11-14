{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Internal unit of the XSLT processor (LandrixXmlXslt), not part of the
  documented API: one run of a compiled stylesheet
  (LandrixXmlXsltCompiler).

  Instructions write to a receiver. A tree receiver builds a tree
  (element content: atomic values become text, separated by a space when
  adjacent; nodes are copied; attributes go to the element just started,
  where a later one replaces an earlier one with the same name), fixing
  the namespaces when an element's start is complete. A sequence
  receiver collects the items of a sequence constructor (xsl:variable
  with "as", template results with "as"): nodes it constructs become
  trees without document node, added to the evaluator with AddTree.

  The principal result is built as a tree; LandrixXmlXsltOutput
  serializes it. Templates and stylesheet functions run in frames of
  their own (PushFrame). XPath errors escaping an instruction get its
  module and line. }

unit LandrixXmlXsltRuntime;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  Contnrs,
  LandrixXmlBase,
  LandrixXmlXsdTypes,
  LandrixXmlXPathTree,
  LandrixXmlXPath,
  LandrixXmlXPathEval,
  LandrixXmlXslt,
  LandrixXmlXsltCompiler,
  LandrixXmlXsltFormat;

type
  TXsltRunSettings = class
  public
    ParamNames: TLandrixXmlUtf8Array;
    ParamKinds: array of Integer;
    ParamValues: TLandrixXmlUtf8Array;
    ParamTrees: array of TLandrixXmlXPathTree;
    InitialMode: TLandrixXmlUtf8;
    InitialTemplate: TLandrixXmlUtf8;
    Resolver: TLandrixXmlXsltResolver;
    ImplicitTimeZone: Integer;
    HasClock: Boolean;
    Clock: TLandrixXmlXsdDateTime;
    MaxDepth: Integer;
    MaxTemplateDepth: Integer;
    { TLandrixXmlXsltMessage, owned by the transformer }
    Messages: TObjectList;
    procedure AddParameter(const Name: TLandrixXmlUtf8; Kind: Integer; const Value: TLandrixXmlUtf8;
      Tree: TLandrixXmlXPathTree);
  end;

{ Runs Compiled on Source (nil: an empty document) into Target. }
procedure XsltRun(Compiled: TObject; Settings: TXsltRunSettings; Source, Target: TLandrixXmlXPathTree);

implementation

uses
  LandrixXmlReader;

type
  TRun = class;

  TReceiver = class
  protected
    FRun: TRun;
  public
    constructor Create(ARun: TRun);
    procedure StartElement(const Uri, Prefix, Local: TLandrixXmlUtf8); virtual; abstract;
    procedure NamespaceNode(const Prefix, Uri: TLandrixXmlUtf8); virtual; abstract;
    procedure Attribute(const Uri, Prefix, Local, Value: TLandrixXmlUtf8); virtual; abstract;
    procedure Characters(const S: TLandrixXmlUtf8); virtual; abstract;
    procedure Comment(const S: TLandrixXmlUtf8); virtual; abstract;
    procedure ProcessingInstruction(const Target, S: TLandrixXmlUtf8); virtual; abstract;
    procedure EndElement; virtual; abstract;
    { an item of a sequence (xsl:sequence, xsl:copy-of: Copy) }
    procedure Item(const It: TLandrixXmlXPathItem; Copy: Boolean);
    procedure AddItem(const It: TLandrixXmlXPathItem); virtual; abstract;
    { a copy of a node (in a tree any node is copied: AddItem) }
    procedure CopyItem(const It: TLandrixXmlXPathItem); virtual;
  end;

  { builds Tree (BeginBuild called by the creator) }
  TTreeReceiver = class(TReceiver)
  private
    FTree: TLandrixXmlXPathTree;
    FPending: Boolean;
    FUri, FPrefix, FLocal: TLandrixXmlUtf8;
    FNsPrefixes, FNsUris: TLandrixXmlUtf8Array;
    FAttrUris, FAttrPrefixes, FAttrLocals, FAttrValues: TLandrixXmlUtf8Array;
    FAttrCount: Integer;
    { the namespaces in scope: bindings and the count per open element }
    FScopePrefixes, FScopeUris: TLandrixXmlUtf8Array;
    FScopeCount: Integer;
    FMarks: array of Integer;
    FDepth: Integer;
    FLastAtomic: Boolean;
    FDocument: Boolean;
    { an attribute at the top is its value as text (xsl:message) }
    FAttributesAsText: Boolean;
    procedure Flush;
    function FreePrefix(const Prefix, Uri: TLandrixXmlUtf8): TLandrixXmlUtf8;
    function Taken(const Prefix, Uri: TLandrixXmlUtf8): Boolean;
    function Bound(const Prefix: TLandrixXmlUtf8; out Uri: TLandrixXmlUtf8): Boolean;
    function InScope(const Prefix: TLandrixXmlUtf8; out Uri: TLandrixXmlUtf8): Boolean;
    procedure Declare(const Prefix, Uri: TLandrixXmlUtf8);
    procedure Content;
  public
    constructor Create(ARun: TRun; Tree: TLandrixXmlXPathTree; Document: Boolean);
    procedure StartElement(const Uri, Prefix, Local: TLandrixXmlUtf8); override;
    procedure NamespaceNode(const Prefix, Uri: TLandrixXmlUtf8); override;
    procedure Attribute(const Uri, Prefix, Local, Value: TLandrixXmlUtf8); override;
    procedure Characters(const S: TLandrixXmlUtf8); override;
    procedure Comment(const S: TLandrixXmlUtf8); override;
    procedure ProcessingInstruction(const Target, S: TLandrixXmlUtf8); override;
    procedure EndElement; override;
    procedure AddItem(const It: TLandrixXmlXPathItem); override;
    { completes the tree (EndBuild) }
    procedure Finish;
    property Depth: Integer read FDepth;
  end;

  TSequenceReceiver = class(TReceiver)
  private
    FItems: TLandrixXmlXPathSequence;
    FInner: TTreeReceiver;
    FInnerTree: TLandrixXmlXPathTree;
    procedure StartNode;
    procedure EndNode;
  public
    constructor Create(ARun: TRun);
    destructor Destroy; override;
    procedure StartElement(const Uri, Prefix, Local: TLandrixXmlUtf8); override;
    procedure NamespaceNode(const Prefix, Uri: TLandrixXmlUtf8); override;
    procedure Attribute(const Uri, Prefix, Local, Value: TLandrixXmlUtf8); override;
    procedure Characters(const S: TLandrixXmlUtf8); override;
    procedure Comment(const S: TLandrixXmlUtf8); override;
    procedure ProcessingInstruction(const Target, S: TLandrixXmlUtf8); override;
    procedure EndElement; override;
    procedure AddItem(const It: TLandrixXmlXPathItem); override;
    procedure CopyItem(const It: TLandrixXmlXPathItem); override;
    property Items: TLandrixXmlXPathSequence read FItems;
  end;

  { a parameter value supplied to a template }
  TSupplied = record
    Name: TLandrixXmlUtf8;
    Value: TLandrixXmlXPathSequence;
  end;
  TSuppliedArray = array of TSupplied;

  TRun = class
  private
    FC: TXsltCompiled;
    FSettings: TXsltRunSettings;
    FEvaluator: TLandrixXmlXPathEvaluator;
    FSource: TLandrixXmlXPathTree;
    FEmpty: TLandrixXmlXPathTree;
    FTrees: TObjectList;
    FFunctions: TList;
    FDefs: TObjectList;
    FTemplateDepth: Integer;
    FParamExprs: TObjectList;
    { current(): an atomic item of the instruction (a node: CurrentNode) }
    FCurrent: TLandrixXmlXPathSequence;
    FResolver: TLandrixXmlXsltResolver;
    FOwnResolver: Boolean;
    { documents read by doc() and document(): URI and node number }
    FDocUris: TStringList;
    FDocNodes: array of Integer;
    FTrue, FFalse: TLandrixXmlXPathExpression;
    { xsl:number value: round(number(.)) as an integer, -1 for NaN }
    FRoundExpr: TLandrixXmlXPathExpression;
    { number(.), to compare numeric keys }
    FNumberExpr: TLandrixXmlXPathExpression;
    { xs:double(.): a function argument of type xs:double }
    FDoubleExpr: TLandrixXmlXPathExpression;
    { . * 100 and . * 1000 for a double in a percent or per-mille picture }
    FTimes100Expr, FTimes1000Expr: TLandrixXmlXPathExpression;
    { the current group and its key (xsl:for-each-group); FGroupActive
      False where there is none (XTDE1061) }
    FGroup: TLandrixXmlXPathSequence;
    FGroupKey: TLandrixXmlXPathSequence;
    FGroupActive: Boolean;
    FGroupLazyDepth: Integer;
    { group-by or group-adjacent: there is a grouping key }
    FGroupHasKey: Boolean;
    { generate-id(): the tree last asked and the numbers of its nodes }
    FIdTree: TLandrixXmlXPathTree;
    FIdNumbers: array of Integer;
    { the canonical form of a QName, xs:dateTime or xs:time key }
    FKeyNormExpr: TLandrixXmlXPathExpression;
    { the indexes of xsl:key built so far (TKeyIndex) }
    FKeyIndexes: TObjectList;
    { per module: static-base-uri() and resolve-uri(.) with its URI }
    FBaseExprs: TObjectList;
    { xs:dateTime?, xs:date?, xs:time? (the first argument of the format
      functions) }
    FDateTypes: array[TXsltDateKind] of TLandrixXmlXPathSequenceType;
    FStringType, FOptionalStringType: TLandrixXmlXPathSequenceType;
    function FormatDate(Kind: TXsltDateKind; const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function AtomKey(const It: TLandrixXmlXPathItem): TLandrixXmlUtf8;
    function KeyFunction(const Args: array of TLandrixXmlXPathSequence;
      const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
    function KeyIndex(K: TXsltKey; Root: Integer): TObject;
    function GenerateId(Node: Integer): TLandrixXmlUtf8;
    function FormatNumber(const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    procedure DoForEachGroup(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      R: TReceiver);
    function LoadDocument(const Href, Base: TLandrixXmlUtf8; Available: Boolean): Integer;
    function DocFunction(Kind, Module: Integer; const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    function Host(Evaluator: TLandrixXmlXPathEvaluator; Def: TLandrixXmlXPathFunctionDef;
      const Args: array of TLandrixXmlXPathSequence; const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
    procedure Fail(Instr: TXsltInstr; const Code, Msg: string);
    function Eval(Instr: TXsltInstr; Expr: TLandrixXmlXPathExpression;
      const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
    function SimpleContent(const S: TLandrixXmlXPathSequence; const Separator: TLandrixXmlUtf8): TLandrixXmlUtf8;
    function EvalString(Instr: TXsltInstr; Expr: TLandrixXmlXPathExpression;
      const Focus: TLandrixXmlXPathFocus; const Separator: TLandrixXmlUtf8): TLandrixXmlUtf8;
    function EvalAvt(Instr: TXsltInstr; Avt: TXsltAvt; const Focus: TLandrixXmlXPathFocus): TLandrixXmlUtf8;
    function BodyString(Body: TObjectList; const Focus: TLandrixXmlXPathFocus;
      const Mode: TXsltMode; const Separator: TLandrixXmlUtf8): TLandrixXmlUtf8;
    function BodySequence(Body: TObjectList; const Focus: TLandrixXmlXPathFocus;
      const Mode: TXsltMode): TLandrixXmlXPathSequence;
    function ContentDocument(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus;
      const Mode: TXsltMode): TLandrixXmlXPathSequence;
    function BodyDocument(Body: TObjectList; const Focus: TLandrixXmlXPathFocus;
      const Mode: TXsltMode): TLandrixXmlXPathSequence;
    function VariableValue(Instr: TXsltInstr; Select: TLandrixXmlXPathExpression; Body: TObjectList;
      HasAs: Boolean; const AsType: TLandrixXmlXPathSequenceType; const Name: TLandrixXmlUtf8;
      const Focus: TLandrixXmlXPathFocus; const Mode: TXsltMode): TLandrixXmlXPathSequence;
    procedure Exec(Body: TObjectList; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure ExecInstr(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure LiteralElement(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      R: TReceiver);
    procedure ComputedName(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Element: Boolean;
      out Uri, Prefix, Local: TLandrixXmlUtf8);
    procedure CopyInstr(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure ExecCore(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure DoValueOf(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure DoVariable(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode);
    function Test(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus): Boolean;
    function ChosenBody(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus): TObjectList;
    procedure DoForEach(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure DoSequence(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; R: TReceiver);
    procedure DoElement(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure DoAttribute(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    function InstrText(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode): TLandrixXmlUtf8;
    procedure DoProcessingInstruction(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      R: TReceiver);
    procedure DoMessage(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode);
    procedure DoDocument(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    procedure DoApplyTemplates(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      R: TReceiver);
    procedure DoCallTemplate(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      R: TReceiver);
    function NumberMatches(Instr: TXsltInstr; Count: Boolean; Node, Model: Integer): Boolean;
    procedure DoNumber(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; R: TReceiver);
    procedure Located(Instr: TXsltInstr; E: ELandrixXmlXPathError);
    function Supplied(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode): TSuppliedArray;
    procedure ApplyTemplates(Instr: TXsltInstr; const Nodes: TLandrixXmlXPathSequence; Mode: TXsltMode;
      const Params: TSuppliedArray; R: TReceiver);
    procedure Invoke(T: TXsltTemplate; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      const Params: TSuppliedArray; R: TReceiver);
    procedure BindParams(T: TXsltTemplate; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      const Params: TSuppliedArray);
    procedure TypedBody(T: TXsltTemplate; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
    function FindRule(Mode: TXsltMode; Node: Integer): TXsltRule;
    function CallFunction(T: TXsltTemplate; const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
    procedure BuiltIn(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
      const Params: TSuppliedArray; R: TReceiver);
    procedure BindGlobals;
  public
    constructor Create(Compiled: TXsltCompiled; Settings: TXsltRunSettings; Source: TLandrixXmlXPathTree);
    destructor Destroy; override;
    { a finished tree: owned by the run, added to the evaluator }
    function AddTree(Tree: TLandrixXmlXPathTree): Integer;
    procedure CopyNode(Node: Integer; R: TReceiver);
    procedure Start(Target: TLandrixXmlXPathTree);
    property Evaluator: TLandrixXmlXPathEvaluator read FEvaluator;
  end;

function NoFocus: TLandrixXmlXPathFocus;
begin
  Result.Node := -1;
  Result.Item := LandrixXmlXPathEmpty;
  Result.Position := 0;
  Result.Size := 0;
end;

function NodeFocus(Node, Position, Size: Integer): TLandrixXmlXPathFocus;
begin
  Result.Node := Node;
  Result.Item := LandrixXmlXPathEmpty;
  Result.Position := Position;
  Result.Size := Size;
end;

function ItemFocus(const It: TLandrixXmlXPathItem; Position, Size: Integer): TLandrixXmlXPathFocus;
begin
  if It.Kind = xikNode then
    Result := NodeFocus(It.Node, Position, Size)
  else
  begin
    Result.Node := -1;
    Result.Item := LandrixXmlXPathEmpty;
    LandrixXmlXPathAppend(Result.Item, It);
    Result.Position := Position;
    Result.Size := Size;
  end;
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

{ A comment's text as XSLT 2.0 (11.6) repairs it: a space after a "-"
  followed by "-" or at the end. }
function CommentText(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    Result := Result + Copy(S, I, 1);
    if (S[I] = '-') and ((I = Length(S)) or (S[I + 1] = '-')) then
      Result := Result + ' ';
  end;
end;

{ A processing instruction's text (11.7): "?>" becomes "? >", leading
  white space goes. }
function PIText(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and (S[I] in [#9, #10, #13, ' ']) do
    Inc(I);
  Result := '';
  while I <= Length(S) do
  begin
    Result := Result + Copy(S, I, 1);
    if (S[I] = '?') and (I < Length(S)) and (S[I + 1] = '>') then
      Result := Result + ' ';
    Inc(I);
  end;
end;

{ --- TXsltRunSettings -------------------------------------------------------- }

procedure TXsltRunSettings.AddParameter(const Name: TLandrixXmlUtf8; Kind: Integer; const Value: TLandrixXmlUtf8;
  Tree: TLandrixXmlXPathTree);
var
  N: Integer;
begin
  N := Integer(Length(ParamNames));
  SetLength(ParamNames, N + 1);
  SetLength(ParamKinds, N + 1);
  SetLength(ParamValues, N + 1);
  SetLength(ParamTrees, N + 1);
  ParamNames[N] := Name;
  ParamKinds[N] := Kind;
  ParamValues[N] := Value;
  ParamTrees[N] := Tree;
end;

{ --- receivers ------------------------------------------------------------------ }

constructor TReceiver.Create(ARun: TRun);
begin
  inherited Create;
  FRun := ARun;
end;

procedure TReceiver.Item(const It: TLandrixXmlXPathItem; Copy: Boolean);
begin
  if Copy and (It.Kind = xikNode) then
    CopyItem(It)
  else
    AddItem(It);
end;

procedure TReceiver.CopyItem(const It: TLandrixXmlXPathItem);
begin
  AddItem(It);
end;

constructor TTreeReceiver.Create(ARun: TRun; Tree: TLandrixXmlXPathTree; Document: Boolean);
begin
  inherited Create(ARun);
  FTree := Tree;
  FDocument := Document;
  SetLength(FMarks, 16);
end;

function TTreeReceiver.InScope(const Prefix: TLandrixXmlUtf8; out Uri: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  if Prefix = 'xml' then
  begin
    Uri := LandrixXmlNamespaceXml;
    Result := True;
    Exit;
  end;
  for I := FScopeCount - 1 downto 0 do
    if FScopePrefixes[I] = Prefix then
    begin
      Uri := FScopeUris[I];
      Result := (Uri <> '') or (Prefix = '');
      Exit;
    end;
  Uri := '';
  Result := Prefix = '';
end;

{ the binding of Prefix for the pending element: its declarations, then
  the scope }
function TTreeReceiver.Bound(const Prefix: TLandrixXmlUtf8; out Uri: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  for I := 0 to Integer(Length(FNsPrefixes)) - 1 do
    if FNsPrefixes[I] = Prefix then
    begin
      Uri := FNsUris[I];
      Result := True;
      Exit;
    end;
  Result := InScope(Prefix, Uri);
end;

procedure TTreeReceiver.Declare(const Prefix, Uri: TLandrixXmlUtf8);
var
  I: Integer;
begin
  for I := 0 to Integer(Length(FNsPrefixes)) - 1 do
    if FNsPrefixes[I] = Prefix then
    begin
      FNsUris[I] := Uri;
      Exit;
    end;
  I := Integer(Length(FNsPrefixes));
  SetLength(FNsPrefixes, I + 1);
  SetLength(FNsUris, I + 1);
  FNsPrefixes[I] := Prefix;
  FNsUris[I] := Uri;
end;

{ Whether the pending element cannot bind Prefix to Uri: xml, its own
  declarations, the prefix of its name or of one of its attributes give
  the prefix another URI (an ancestor's binding can be redeclared, as
  Saxon does). }
function TTreeReceiver.Taken(const Prefix, Uri: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := True;
  if Prefix = 'xml' then
    Exit;
  for I := 0 to Integer(Length(FNsPrefixes)) - 1 do
    if (FNsPrefixes[I] = Prefix) and (FNsUris[I] <> Uri) then
      Exit;
  if (Prefix = FPrefix) and (FUri <> Uri) then
    Exit;
  for I := 0 to FAttrCount - 1 do
    if (FAttrUris[I] <> '') and (FAttrPrefixes[I] = Prefix) and (FAttrUris[I] <> Uri) then
      Exit;
  Result := False;
end;

{ a prefix for Uri the pending element can declare, as Saxon makes one:
  the prefix, "_" and a number from 1 (for none "ns0" itself first) }
function TTreeReceiver.FreePrefix(const Prefix, Uri: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  N: Integer;
  Base: TLandrixXmlUtf8;
begin
  Base := Prefix;
  if Base = '' then
  begin
    Base := 'ns0';
    Result := Base;
    if not Taken(Result, Uri) then
      Exit;
  end;
  N := 1;
  repeat
    Result := Base + '_' + LandrixXmlStringToUtf8(IntToStr(N));
    Inc(N);
  until not Taken(Result, Uri);
end;

procedure TTreeReceiver.Flush;
var
  I, J, N: Integer;
  Uri, P: TLandrixXmlUtf8;
  Prefixes, Uris: TLandrixXmlUtf8Array;
begin
  if not FPending then
    Exit;
  FPending := False;
  { the element's name }
  if FUri = '' then
  begin
    FPrefix := '';
    Bound('', Uri);
    if Uri <> '' then
    begin
      { the undeclaration first, as Saxon writes it (a declaration of the
        default namespace the element was given is replaced) }
      N := 0;
      while (N < Length(FNsPrefixes)) and (FNsPrefixes[N] <> '') do
        Inc(N);
      if N = Length(FNsPrefixes) then
      begin
        SetLength(FNsPrefixes, N + 1);
        SetLength(FNsUris, N + 1);
      end;
      for I := N downto 1 do
      begin
        FNsPrefixes[I] := FNsPrefixes[I - 1];
        FNsUris[I] := FNsUris[I - 1];
      end;
      FNsPrefixes[0] := '';
      FNsUris[0] := '';
    end;
  end
  else if FUri = LandrixXmlNamespaceXml then
    FPrefix := 'xml'
  else if not Bound(FPrefix, Uri) or (Uri <> FUri) then
  begin
    { a prefix the declarations already give another URI: another prefix }
    if FPrefix = 'xml' then
    begin
      FPrefix := 'xml_0';
      if Bound(FPrefix, Uri) and (Uri <> FUri) then
        FPrefix := FreePrefix('xml', FUri);
    end
    else
      for I := 0 to Integer(Length(FNsPrefixes)) - 1 do
        if (FNsPrefixes[I] = FPrefix) and (FNsUris[I] <> FUri) then
        begin
          FPrefix := FreePrefix(FPrefix, FUri);
          Break;
        end;
    Declare(FPrefix, FUri);
  end;
  { attributes in a namespace need a prefix bound to it }
  for I := 0 to FAttrCount - 1 do
    if FAttrUris[I] <> '' then
    begin
      if (FAttrPrefixes[I] <> '') and Bound(FAttrPrefixes[I], Uri) and (Uri = FAttrUris[I]) then
        Continue;
      P := '';
      for J := 0 to Integer(Length(FNsPrefixes)) - 1 do
        if (FNsPrefixes[J] <> '') and (FNsUris[J] = FAttrUris[I]) then
          P := FNsPrefixes[J];
      if P = '' then
        for J := FScopeCount - 1 downto 0 do
          if (FScopePrefixes[J] <> '') and (FScopeUris[J] = FAttrUris[I]) and Bound(FScopePrefixes[J], Uri) and
            (Uri = FAttrUris[I]) then
          begin
            P := FScopePrefixes[J];
            Break;
          end;
      if P = '' then
      begin
        P := FAttrPrefixes[I];
        if (P = '') or Taken(P, FAttrUris[I]) then
          P := FreePrefix(P, FAttrUris[I]);
        Declare(P, FAttrUris[I]);
      end;
      FAttrPrefixes[I] := P;
    end
    else
      FAttrPrefixes[I] := '';
  { declarations the scope already has are not repeated }
  Prefixes := nil;
  Uris := nil;
  for I := 0 to Integer(Length(FNsPrefixes)) - 1 do
  begin
    if InScope(FNsPrefixes[I], Uri) and (Uri = FNsUris[I]) then
      Continue;
    if (FNsPrefixes[I] = '') and (FNsUris[I] = '') and not InScope('', Uri) then
      Continue;
    if (FNsPrefixes[I] = '') and (FNsUris[I] = '') and (Uri = '') then
      Continue;
    N := Integer(Length(Prefixes));
    SetLength(Prefixes, N + 1);
    SetLength(Uris, N + 1);
    Prefixes[N] := FNsPrefixes[I];
    Uris[N] := FNsUris[I];
  end;
  FTree.BuildStartElement(FUri, FPrefix, FLocal);
  for I := 0 to Integer(Length(Prefixes)) - 1 do
    FTree.BuildNamespace(Prefixes[I], Uris[I]);
  for I := 0 to FAttrCount - 1 do
    FTree.BuildAttribute(FAttrUris[I], FAttrPrefixes[I], FAttrLocals[I], FAttrValues[I]);
  { the scope of the element's content }
  if FDepth >= Length(FMarks) then
    SetLength(FMarks, 2 * FDepth + 16);
  FMarks[FDepth - 1] := FScopeCount;
  for I := 0 to Integer(Length(Prefixes)) - 1 do
  begin
    if FScopeCount = Length(FScopePrefixes) then
    begin
      SetLength(FScopePrefixes, 2 * FScopeCount + 8);
      SetLength(FScopeUris, 2 * FScopeCount + 8);
    end;
    FScopePrefixes[FScopeCount] := Prefixes[I];
    FScopeUris[FScopeCount] := Uris[I];
    Inc(FScopeCount);
  end;
  FNsPrefixes := nil;
  FNsUris := nil;
  FAttrCount := 0;
end;

procedure TTreeReceiver.Content;
begin
  Flush;
  FLastAtomic := False;
end;

procedure TTreeReceiver.StartElement(const Uri, Prefix, Local: TLandrixXmlUtf8);
begin
  Content;
  FPending := True;
  FUri := Uri;
  FPrefix := Prefix;
  FLocal := Local;
  FNsPrefixes := nil;
  FNsUris := nil;
  FAttrCount := 0;
  Inc(FDepth);
end;

procedure TTreeReceiver.NamespaceNode(const Prefix, Uri: TLandrixXmlUtf8);
var
  Existing: TLandrixXmlUtf8;
  I: Integer;
begin
  if not FPending then
    raise ELandrixXmlXPathError.CreateXPath('XTDE0410', 'a namespace node after the content of an element');
  if Prefix = 'xml' then
    Exit;
  { the element's own declarations decide a clash (the element's name) }
  for I := 0 to Integer(Length(FNsPrefixes)) - 1 do
    if FNsPrefixes[I] = Prefix then
    begin
      Existing := FNsUris[I];
      if Existing <> Uri then
        raise ELandrixXmlXPathError.CreateXPath('XTDE0430', 'two namespace nodes with the prefix "' +
          LandrixXmlUtf8ToString(Prefix) + '"');
      Exit;
    end;
  Declare(Prefix, Uri);
end;

procedure TTreeReceiver.Attribute(const Uri, Prefix, Local, Value: TLandrixXmlUtf8);
var
  I: Integer;
begin
  if not FPending then
  begin
    if (FDepth = 0) and FAttributesAsText then
    begin
      Characters(Value);
      Exit;
    end;
    if FDepth = 0 then
      raise ELandrixXmlXPathError.CreateXPath('XTDE0420', 'an attribute without an element')
    else
      raise ELandrixXmlXPathError.CreateXPath('XTDE0410', 'an attribute after the content of an element');
  end;
  FLastAtomic := False;
  for I := 0 to FAttrCount - 1 do
    if (FAttrUris[I] = Uri) and (FAttrLocals[I] = Local) then
    begin
      FAttrPrefixes[I] := Prefix;
      FAttrValues[I] := Value;
      Exit;
    end;
  if FAttrCount = Length(FAttrUris) then
  begin
    SetLength(FAttrUris, 2 * FAttrCount + 8);
    SetLength(FAttrPrefixes, 2 * FAttrCount + 8);
    SetLength(FAttrLocals, 2 * FAttrCount + 8);
    SetLength(FAttrValues, 2 * FAttrCount + 8);
  end;
  FAttrUris[FAttrCount] := Uri;
  FAttrPrefixes[FAttrCount] := Prefix;
  FAttrLocals[FAttrCount] := Local;
  FAttrValues[FAttrCount] := Value;
  Inc(FAttrCount);
end;

procedure TTreeReceiver.Characters(const S: TLandrixXmlUtf8);
begin
  { an empty text node still separates atomic values }
  if S = '' then
  begin
    FLastAtomic := False;
    Exit;
  end;
  Content;
  FTree.BuildText(S);
end;

procedure TTreeReceiver.Comment(const S: TLandrixXmlUtf8);
begin
  Content;
  FTree.BuildComment(S);
end;

procedure TTreeReceiver.ProcessingInstruction(const Target, S: TLandrixXmlUtf8);
begin
  Content;
  FTree.BuildProcessingInstruction(Target, S);
end;

procedure TTreeReceiver.EndElement;
begin
  Content;
  FTree.BuildEndElement;
  Dec(FDepth);
  FScopeCount := FMarks[FDepth];
end;

procedure TTreeReceiver.AddItem(const It: TLandrixXmlXPathItem);
var
  S: TLandrixXmlUtf8;
begin
  if It.Kind <> xikNode then
  begin
    S := FRun.Evaluator.ItemString(It);
    if FLastAtomic then
      S := ' ' + S;
    if S <> '' then
    begin
      Flush;
      FTree.BuildText(S);
    end;
    FLastAtomic := True;
    Exit;
  end;
  FRun.CopyNode(It.Node, Self);
end;

procedure TTreeReceiver.Finish;
begin
  Flush;
  FTree.EndBuild;
end;

constructor TSequenceReceiver.Create(ARun: TRun);
begin
  inherited Create(ARun);
  FItems := LandrixXmlXPathEmpty;
end;

destructor TSequenceReceiver.Destroy;
begin
  FInner.Free;
  FInnerTree.Free;
  inherited Destroy;
end;

{ a node at the top: a tree of its own }
procedure TSequenceReceiver.StartNode;
begin
  FInnerTree := TLandrixXmlXPathTree.Create;
  FInnerTree.BeginBuild(False);
  FInner := TTreeReceiver.Create(FRun, FInnerTree, False);
end;

procedure TSequenceReceiver.EndNode;
var
  Base: Integer;
  T: TLandrixXmlXPathTree;
begin
  FInner.Finish;
  FInner.Free;
  FInner := nil;
  T := FInnerTree;
  FInnerTree := nil;
  Base := FRun.AddTree(T);
  LandrixXmlXPathAppend(FItems, LandrixXmlXPathNodeItem(Base).Items[0]);
end;

procedure TSequenceReceiver.StartElement(const Uri, Prefix, Local: TLandrixXmlUtf8);
begin
  if FInner = nil then
    StartNode;
  FInner.StartElement(Uri, Prefix, Local);
end;

procedure TSequenceReceiver.NamespaceNode(const Prefix, Uri: TLandrixXmlUtf8);
begin
  if FInner = nil then
    raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT: a namespace node in a sequence is not supported');
  FInner.NamespaceNode(Prefix, Uri);
end;

procedure TSequenceReceiver.Attribute(const Uri, Prefix, Local, Value: TLandrixXmlUtf8);
begin
  if FInner <> nil then
  begin
    FInner.Attribute(Uri, Prefix, Local, Value);
    Exit;
  end;
  StartNode;
  FInnerTree.BuildAttribute(Uri, Prefix, Local, Value);
  EndNode;
end;

procedure TSequenceReceiver.Characters(const S: TLandrixXmlUtf8);
begin
  if FInner <> nil then
  begin
    FInner.Characters(S);
    Exit;
  end;
  StartNode;
  FInnerTree.BuildText(S);
  EndNode;
end;

procedure TSequenceReceiver.Comment(const S: TLandrixXmlUtf8);
begin
  if FInner <> nil then
  begin
    FInner.Comment(S);
    Exit;
  end;
  StartNode;
  FInnerTree.BuildComment(S);
  EndNode;
end;

procedure TSequenceReceiver.ProcessingInstruction(const Target, S: TLandrixXmlUtf8);
begin
  if FInner <> nil then
  begin
    FInner.ProcessingInstruction(Target, S);
    Exit;
  end;
  StartNode;
  FInnerTree.BuildProcessingInstruction(Target, S);
  EndNode;
end;

procedure TSequenceReceiver.EndElement;
begin
  FInner.EndElement;
  if FInner.Depth = 0 then
    EndNode;
end;

procedure TSequenceReceiver.AddItem(const It: TLandrixXmlXPathItem);
begin
  if FInner <> nil then
    FInner.AddItem(It)
  else
    LandrixXmlXPathAppend(FItems, It);
end;

procedure TSequenceReceiver.CopyItem(const It: TLandrixXmlXPathItem);
var
  T: TLandrixXmlXPathTree;
  Builder: TTreeReceiver;
  B: Integer;
  Tree: TLandrixXmlXPathTree;
begin
  if FInner <> nil then
  begin
    FInner.AddItem(It);
    Exit;
  end;
  Tree := FRun.Evaluator.TreeOfNode(It.Node, B);
  { an attribute, text, comment or processing instruction: a tree of its
    own through this receiver }
  if not (Tree.Kind[It.Node - B] in [xnkDocument, xnkElement]) then
  begin
    FRun.CopyNode(It.Node, Self);
    Exit;
  end;
  { a copy: a new tree (a document stays a document) }
  T := TLandrixXmlXPathTree.Create;
  try
    T.BeginBuild(Tree.Kind[It.Node - B] = xnkDocument);
    Builder := TTreeReceiver.Create(FRun, T, Tree.Kind[It.Node - B] = xnkDocument);
    try
      FRun.CopyNode(It.Node, Builder);
      Builder.Finish;
    finally
      Builder.Free;
    end;
  except
    T.Free;
    raise;
  end;
  B := FRun.AddTree(T);
  LandrixXmlXPathAppend(FItems, LandrixXmlXPathNodeItem(B).Items[0]);
end;

{ --- the run ------------------------------------------------------------------------ }

type
  { the node numbers of one key value }
  TKeyNodes = class
  public
    Nodes: array of Integer;
    Count: Integer;
    procedure Add(Node: Integer);
  end;

  { the index of a key in one tree: key value (AtomKey) -> TKeyNodes }
  TKeyIndex = class
  public
    Key: TXsltKey;
    Root: Integer;
    { being built (a use expression that needs the same key: XTDE0640) }
    Building: Boolean;
    Map: TXsltStringList;
    constructor Create;
    destructor Destroy; override;
  end;

procedure TKeyNodes.Add(Node: Integer);
begin
  if (Count > 0) and (Nodes[Count - 1] = Node) then
    Exit;
  if Count = Length(Nodes) then
    SetLength(Nodes, 2 * Count + 4);
  Nodes[Count] := Node;
  Inc(Count);
end;

constructor TKeyIndex.Create;
begin
  inherited Create;
  Map := TXsltStringList.Create;
  Map.CaseSensitive := True;
  Map.Sorted := True;
end;

destructor TKeyIndex.Destroy;
var
  I: Integer;
begin
  for I := 0 to Integer(Map.Count) - 1 do
    Map.Objects[I].Free;
  Map.Free;
  inherited Destroy;
end;

{ S with each ' doubled (in an XPath string literal) }
function ReplaceQuotes(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    Result := Result + Copy(S, I, 1);
    if S[I] = '''' then
      Result := Result + '''';
  end;
end;

constructor TRun.Create(Compiled: TXsltCompiled; Settings: TXsltRunSettings; Source: TLandrixXmlXPathTree);
var
  I: Integer;
  Lit: TLandrixXmlUtf8;
  Def: TLandrixXmlXPathFunctionDef;
begin
  inherited Create;
  FC := Compiled;
  FSettings := Settings;
  FTrees := TObjectList.Create;
  FDefs := TObjectList.Create;
  FFunctions := TList.Create;
  FParamExprs := TObjectList.Create;
  FDocUris := TXsltStringList.Create;
  FDocUris.CaseSensitive := True;
  FResolver := Settings.Resolver;
  if FResolver = nil then
  begin
    FResolver := TLandrixXmlXsltResolver.Create;
    FOwnResolver := True;
  end;
  FSource := Source;
  if FSource = nil then
  begin
    FEmpty := TLandrixXmlXPathTree.Create;
    FSource := FEmpty;
  end;
  FEvaluator := TLandrixXmlXPathEvaluator.Create(FSource);
  FTrue := TLandrixXmlXPathExpression.Create('true()', nil);
  FNumberExpr := TLandrixXmlXPathExpression.Create('number(.)', nil);
  FDoubleExpr := TLandrixXmlXPathExpression.Create('xs:double(.)', nil);
  FTimes100Expr := TLandrixXmlXPathExpression.Create('. * 100', nil);
  FTimes1000Expr := TLandrixXmlXPathExpression.Create('. * 1000', nil);
  FKeyNormExpr := TLandrixXmlXPathExpression.Create(
    'if (. instance of xs:QName) then concat(''{'', namespace-uri-from-QName(.), ''}'', local-name-from-QName(.)) ' +
    'else if (. instance of xs:dateTime and exists(timezone-from-dateTime(.))) ' +
    'then string(adjust-dateTime-to-timezone(., xs:dayTimeDuration(''PT0S''))) ' +
    'else if (. instance of xs:time and exists(timezone-from-time(.))) ' +
    'then string(adjust-time-to-timezone(., xs:dayTimeDuration(''PT0S''))) else string(.)', nil);
  FKeyIndexes := TObjectList.Create;
  FRoundExpr := TLandrixXmlXPathExpression.Create(
    'if (number(.) != number(.) or round(number(.)) lt 0) then -1 ' +
    'else if (round(number(.)) gt 2147483647) then -2 else xs:integer(round(number(.)))', nil);
  FDateTypes[xdkDateTime] := LandrixXmlXPathParseSequenceType('xs:dateTime?', nil);
  FDateTypes[xdkDate] := LandrixXmlXPathParseSequenceType('xs:date?', nil);
  FDateTypes[xdkTime] := LandrixXmlXPathParseSequenceType('xs:time?', nil);
  FStringType := LandrixXmlXPathParseSequenceType('xs:string', nil);
  FOptionalStringType := LandrixXmlXPathParseSequenceType('xs:string?', nil);
  FBaseExprs := TObjectList.Create;
  for I := 0 to Integer(Length(FC.ModuleUris)) - 1 do
  begin
    Lit := '''' + ReplaceQuotes(FC.ModuleUris[I]) + '''';
    if FC.ModuleUris[I] = '' then
    begin
      FBaseExprs.Add(TLandrixXmlXPathExpression.Create('()', nil));
      FBaseExprs.Add(TLandrixXmlXPathExpression.Create('resolve-uri(.)', nil));
    end
    else
    begin
      FBaseExprs.Add(TLandrixXmlXPathExpression.Create('xs:anyURI(' + Lit + ')', nil));
      FBaseExprs.Add(TLandrixXmlXPathExpression.Create('resolve-uri(., ' + Lit + ')', nil));
    end;
  end;
  FFalse := TLandrixXmlXPathExpression.Create('false()', nil);
  { one definition per function of the static contexts, in their order }
  for I := 0 to Integer(Length(FC.FunctionNames)) - 1 do
  begin
    Def := TLandrixXmlXPathFunctionDef.Create;
    Def.Name := LandrixXmlUtf8ToString(XsltClarkOf(FC.FunctionUris[I], FC.FunctionNames[I]));
    Def.Host := Host;
    Def.Tag := I;
    FDefs.Add(Def);
    FFunctions.Add(Def);
  end;
  FEvaluator.Functions := FFunctions;
  FEvaluator.MaxDepth := Settings.MaxDepth;
  FEvaluator.ImplicitTimeZone := Settings.ImplicitTimeZone;
  if Settings.HasClock then
    FEvaluator.CurrentDateTime := Settings.Clock;
end;

destructor TRun.Destroy;
begin
  if FOwnResolver then
    FResolver.Free;
  FDocUris.Free;
  FEvaluator.Free;
  FTrue.Free;
  FRoundExpr.Free;
  FNumberExpr.Free;
  FDoubleExpr.Free;
  FKeyNormExpr.Free;
  FTimes100Expr.Free;
  FTimes1000Expr.Free;
  FKeyIndexes.Free;
  FBaseExprs.Free;
  FFalse.Free;
  FParamExprs.Free;
  FFunctions.Free;
  FDefs.Free;
  FTrees.Free;
  FEmpty.Free;
  inherited Destroy;
end;

{ The node number of the document Href (relative to Base), read once per
  run; -1 if it is not available (Available) or else FODC0002. }
function TRun.LoadDocument(const Href, Base: TLandrixXmlUtf8; Available: Boolean): Integer;
var
  Uri, Key: TLandrixXmlUtf8;
  Content: TStream;
  Tree: TLandrixXmlXPathTree;
  Reader: TLandrixXmlReader;
  I: Integer;
begin
  Result := -1;
  Content := nil;
  { a document read before is not resolved again }
  Key := LandrixXmlXPathResolveUri(Href, Base);
  I := FDocUris.IndexOf(LandrixXmlUtf8ToString(Key));
  if I >= 0 then
    Result := FDocNodes[I]
  else if FResolver.Resolve(xrkDocument, Base, Href, Uri, Content) then
  begin
    I := FDocUris.IndexOf(LandrixXmlUtf8ToString(Uri));
    if I >= 0 then
    begin
      Content.Free;
      Result := FDocNodes[I];
    end
    else
    begin
      Tree := TLandrixXmlXPathTree.Create;
      Reader := TLandrixXmlReader.Create;
      try
        try
          Reader.LoadFromStream(Content);
          Tree.LoadFromReader(Reader);
          Tree.BaseUri := Uri;
          Result := AddTree(Tree);
          Tree := nil;
        except
          on E: ELandrixXmlError do
            if not Available then
              raise ELandrixXmlXPathError.CreateXPath('FODC0002', 'the document ' + LandrixXmlUtf8ToString(Uri) +
                ' is not well-formed: ' + E.Message);
        end;
      finally
        Reader.Free;
        Tree.Free;
        Content.Free;
      end;
      FDocUris.Add(LandrixXmlUtf8ToString(Uri));
      SetLength(FDocNodes, FDocUris.Count);
      FDocNodes[Integer(FDocUris.Count) - 1] := Result;
    end;
    if Key <> Uri then
    begin
      FDocUris.Add(LandrixXmlUtf8ToString(Key));
      SetLength(FDocNodes, FDocUris.Count);
      FDocNodes[Integer(FDocUris.Count) - 1] := Result;
    end;
  end;
  if (Result < 0) and not Available then
    raise ELandrixXmlXPathError.CreateXPath('FODC0002', 'the document ' + LandrixXmlUtf8ToString(Href) +
      ' is not available');
end;

{ doc(), doc-available(), document() of a module: relative URIs against
  the module's base URI (document(): a node's own base URI) }
function TRun.DocFunction(Kind, Module: Integer; const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  Base, Href, NodeBase: TLandrixXmlUtf8;
  I, N, B, K: Integer;
  T: TLandrixXmlXPathTree;
  Found: Boolean;
begin
  Result := LandrixXmlXPathEmpty;
  if Kind = XfnStaticBaseUri then
  begin
    Result := FEvaluator.EvaluateInFocus(TLandrixXmlXPathExpression(FBaseExprs[2 * Module]), NoFocus);
    Exit;
  end;
  if High(Args) < 0 then
    Exit;
  if Kind = XfnResolveUri then
  begin
    if Args[0].Count > 1 then
      raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'resolve-uri(): one URI was expected');
    if Args[0].Count > 0 then
      Result := FEvaluator.EvaluateInFocus(TLandrixXmlXPathExpression(FBaseExprs[2 * Module + 1]),
        ItemFocus(Args[0].Items[0], 1, 1));
    Exit;
  end;
  Base := FC.ModuleUris[Module];
  if Kind = XfnDocument2 then
    raise ELandrixXmlXsltError.CreateXslt(xecUnsupported, 'FOER0000',
      'document() with a base node is not supported', Base, 0, 0);
  if Kind = XfnDocument then
  begin
    for I := 0 to Args[0].Count - 1 do
    begin
      if Args[0].Items[I].Kind = xikNode then
      begin
        { relative to the base URI of the node (its xml:base included) }
        T := FEvaluator.TreeOfNode(Args[0].Items[I].Node, B);
        Href := T.StringValueUtf8(Args[0].Items[I].Node - B);
        { a node without one (a temporary tree): the module's }
        if not LandrixXmlXPathNodeBaseUri(T, Args[0].Items[I].Node - B, NodeBase) or (NodeBase = '') then
          NodeBase := Base;
        N := LoadDocument(Href, NodeBase, False);
      end
      else
        N := LoadDocument(FEvaluator.ItemString(Args[0].Items[I]), Base, False);
      Found := False;
      for K := 0 to Result.Count - 1 do
        if Result.Items[K].Node = N then
          Found := True;
      if not Found then
        LandrixXmlXPathAppend(Result, LandrixXmlXPathNodeItem(N).Items[0]);
    end;
    Exit;
  end;
  if Args[0].Count = 0 then
  begin
    if Kind = XfnDocAvailable then
      Result := FEvaluator.EvaluateInFocus(FFalse, NoFocus);
    Exit;
  end;
  if Args[0].Count > 1 then
    raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'doc(): one URI was expected');
  Href := FEvaluator.ItemString(Args[0].Items[0]);
  if Kind = XfnDoc then
    Result := LandrixXmlXPathNodeItem(LoadDocument(Href, Base, False))
  else if LoadDocument(Href, Base, True) >= 0 then
    Result := FEvaluator.EvaluateInFocus(FTrue, NoFocus)
  else
    Result := FEvaluator.EvaluateInFocus(FFalse, NoFocus);
end;

function TRun.AddTree(Tree: TLandrixXmlXPathTree): Integer;
begin
  FTrees.Add(Tree);
  Result := FEvaluator.AddTree(Tree);
end;

procedure TRun.Fail(Instr: TXsltInstr; const Code, Msg: string);
begin
  if Instr <> nil then
    raise ELandrixXmlXsltError.CreateXslt(xecXslt, Code, Msg, Instr.Module, Instr.Line, Instr.Column)
  else
    raise ELandrixXmlXsltError.CreateXslt(xecXslt, Code, Msg, '', 0, 0);
end;

function TRun.Host(Evaluator: TLandrixXmlXPathEvaluator; Def: TLandrixXmlXPathFunctionDef;
  const Args: array of TLandrixXmlXPathSequence; const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
var
  G: TXsltGlobal;
  Slot, SavedNode: Integer;
  Arg, SavedCurrent: TLandrixXmlXPathSequence;
begin
  Result := LandrixXmlXPathEmpty;
  if Def.Tag >= FC.UserFunctionBase then
  begin
    Result := CallFunction(TXsltTemplate(FC.UserFunctions[Def.Tag - FC.UserFunctionBase]), Args);
    Exit;
  end;
  if Def.Tag >= XfnFixedCount then
  begin
    Result := DocFunction((Def.Tag - XfnFixedCount) mod XfnPerModule, (Def.Tag - XfnFixedCount) div XfnPerModule,
      Args);
    Exit;
  end;
  case Def.Tag of
    XfnCurrentGroup:
      begin
        if not FGroupActive or (Evaluator.LazyDepth <> FGroupLazyDepth) then
          raise ELandrixXmlXPathError.CreateXPath('XTDE1061', 'there is no current group');
        Result := FGroup;
      end;
    XfnCurrentGroupingKey:
      begin
        if not FGroupActive or not FGroupHasKey or (Evaluator.LazyDepth <> FGroupLazyDepth) then
          raise ELandrixXmlXPathError.CreateXPath('XTDE1071', 'there is no current grouping key');
        Result := FGroupKey;
      end;
    XfnGenerateId0:
      begin
        if Focus.Node < 0 then
        begin
          if Focus.Item.Count = 0 then
            raise ELandrixXmlXPathError.CreateXPath('XPDY0002', 'generate-id(): there is no context item');
          raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'generate-id(): the context item is no node');
        end;
        Result := LandrixXmlXPathStringItem(GenerateId(Focus.Node));
      end;
    XfnGenerateId1:
      begin
        if (High(Args) < 0) or (Args[0].Count = 0) then
          Result := LandrixXmlXPathStringItem('')
        else if (Args[0].Count > 1) or (Args[0].Items[0].Kind <> xikNode) then
          raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'generate-id(): the argument must be one node')
        else
          Result := LandrixXmlXPathStringItem(GenerateId(Args[0].Items[0].Node));
      end;
    XfnKey2, XfnKey3:
      Result := KeyFunction(Args, Focus);
    XfnFormatNumber2, XfnFormatNumber3:
      Result := FormatNumber(Args);
    XfnFormatDateTime2, XfnFormatDateTime5:
      Result := FormatDate(xdkDateTime, Args);
    XfnFormatDate2, XfnFormatDate5:
      Result := FormatDate(xdkDate, Args);
    XfnFormatTime2, XfnFormatTime5:
      Result := FormatDate(xdkTime, Args);
    XfnCurrent:
      begin
        { the node the evaluator has (also that of a global variable
          being evaluated), else an atomic item of the instruction; an
          absent focus is that of a global without a source (an
          instruction's own focus is never absent when it has an item) }
        if Evaluator.CurrentNode >= 0 then
          Result := LandrixXmlXPathNodeItem(Evaluator.CurrentNode)
        else if (Focus.Node < 0) and (Focus.Item.Count = 0) then
          raise ELandrixXmlXPathError.CreateXPath('XPDY0002', 'current(): there is no current item')
        else if FCurrent.Count > 0 then
          Result := FCurrent
        else
          raise ELandrixXmlXPathError.CreateXPath('XPDY0002', 'current(): there is no current item');
      end;
    XfnGlobal:
      begin
        { the value of a global variable with a sequence constructor, in a
          frame of its own (its local variables) }
        Arg := LandrixXmlXPathEmpty;
        if High(Args) >= 0 then
          Arg := Args[0];
        Slot := StrToInt(LandrixXmlUtf8ToString(Evaluator.ItemString(Arg.Items[0])));
        G := TXsltGlobal(FC.Globals[Slot]);
        SavedNode := FEvaluator.CurrentNode;
        SavedCurrent := FCurrent;
        FEvaluator.PushFrame(G.FrameSize);
        try
          Result := VariableValue(nil, nil, G.Body, G.HasAs, G.AsType, G.Name, Focus, FC.FindMode(''));
        finally
          FEvaluator.PopFrame;
          FEvaluator.CurrentNode := SavedNode;
          FCurrent := SavedCurrent;
        end;
      end;
  end;
end;

{ format-dateTime(), format-date(), format-time(): the value converted as
  a function argument, the picture, language and calendar as strings }
function TRun.FormatDate(Kind: TXsltDateKind; const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
const
  Names: array[TXsltDateKind] of string = ('format-date', 'format-time', 'format-dateTime');
var
  V: TLandrixXmlXPathSequence;
  Picture, Language, Calendar: TLandrixXmlUtf8;

  { argument I as xs:string (One) or xs:string? }
  function Str(I: Integer; One: Boolean): TLandrixXmlUtf8;
  var
    S: TLandrixXmlXPathSequence;
  begin
    Result := '';
    if I > High(Args) then
      Exit;
    if One then
      S := FEvaluator.ConvertSequence(Args[I], FStringType, Names[Kind] + '()')
    else
      S := FEvaluator.ConvertSequence(Args[I], FOptionalStringType, Names[Kind] + '()');
    if S.Count > 0 then
      Result := FEvaluator.ItemString(S.Items[0]);
  end;

begin
  Result := LandrixXmlXPathEmpty;
  if High(Args) < 1 then
    Exit;
  V := FEvaluator.ConvertSequence(Args[0], FDateTypes[Kind], Names[Kind] + '()');
  Picture := Str(1, True);
  Language := Str(2, False);
  Calendar := Str(3, False);
  Str(4, False);
  if V.Count = 0 then
    Exit;
  Result := LandrixXmlXPathStringItem(XsltFormatDateTime(FEvaluator.ItemString(V.Items[0]), Kind, Picture,
    Language, Calendar, (High(Args) >= 2) and (Args[2].Count > 0), (High(Args) >= 3) and (Args[3].Count > 0)));
end;

{ XPath errors get the instruction's position }
function TRun.Eval(Instr: TXsltInstr; Expr: TLandrixXmlXPathExpression;
  const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
var
  Saved: TLandrixXmlXPathSequence;
begin
  Saved := FCurrent;
  FCurrent := Focus.Item;
  FEvaluator.CurrentNode := Focus.Node;
  try
    try
      Result := FEvaluator.EvaluateInFocus(Expr, Focus);
    finally
      FCurrent := Saved;
    end;
  except
    on E: ELandrixXmlXsltError do
      raise;
    on E: ELandrixXmlXPathError do
      if Instr <> nil then
        raise ELandrixXmlXsltError.CreateXslt(xecXslt, E.XPathCode,
          System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), Instr.Module, Instr.Line, Instr.Column)
      else
        raise;
  end;
end;

{ Simple content (XSLT 2.0 5.7.2): zero-length text nodes dropped,
  adjacent text nodes merged, the rest joined with the separator. }
function TRun.SimpleContent(const S: TLandrixXmlXPathSequence; const Separator: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I, B: Integer;
  T: TLandrixXmlXPathTree;
  Text: TLandrixXmlUtf8;
  First, PrevText, IsText: Boolean;
begin
  Result := '';
  First := True;
  PrevText := False;
  for I := 0 to Integer(S.Count) - 1 do
  begin
    IsText := False;
    if S.Items[I].Kind = xikNode then
    begin
      T := FEvaluator.TreeOfNode(S.Items[I].Node, B);
      IsText := T.Kind[S.Items[I].Node - B] = xnkText;
    end;
    Text := FEvaluator.ItemString(S.Items[I]);
    if IsText and (Text = '') then
      Continue;
    if not First and not (IsText and PrevText) then
      Result := Result + Separator;
    Result := Result + Text;
    First := False;
    PrevText := IsText;
  end;
end;

function TRun.EvalString(Instr: TXsltInstr; Expr: TLandrixXmlXPathExpression;
  const Focus: TLandrixXmlXPathFocus; const Separator: TLandrixXmlUtf8): TLandrixXmlUtf8;
begin
  Result := SimpleContent(Eval(Instr, Expr, Focus), Separator);
end;

function TRun.EvalAvt(Instr: TXsltInstr; Avt: TXsltAvt; const Focus: TLandrixXmlXPathFocus): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Integer(Length(Avt.Parts)) - 1 do
    if Avt.Exprs[I] = nil then
      Result := Result + Avt.Parts[I]
    else
      Result := Result + EvalString(Instr, Avt.Exprs[I], Focus, ' ');
end;

function TRun.BodySequence(Body: TObjectList; const Focus: TLandrixXmlXPathFocus;
  const Mode: TXsltMode): TLandrixXmlXPathSequence;
var
  R: TSequenceReceiver;
begin
  R := TSequenceReceiver.Create(Self);
  try
    Exec(Body, Focus, Mode, R);
    Result := R.Items;
  finally
    R.Free;
  end;
end;

{ a temporary tree: the document node of the result of Instr's select
  (if any) followed by its body (xsl:message) }
function TRun.ContentDocument(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus;
  const Mode: TXsltMode): TLandrixXmlXPathSequence;
var
  T: TLandrixXmlXPathTree;
  R: TTreeReceiver;
  S: TLandrixXmlXPathSequence;
  I: Integer;
begin
  T := TLandrixXmlXPathTree.Create;
  try
    T.BeginBuild(True);
    R := TTreeReceiver.Create(Self, T, True);
    try
      { as Saxon: an attribute in a message is its value }
      R.FAttributesAsText := True;
      if Instr.Select <> nil then
      begin
        S := Eval(Instr, Instr.Select, Focus);
        for I := 0 to Integer(S.Count) - 1 do
          R.Item(S.Items[I], True);
      end;
      Exec(Instr.Body, Focus, Mode, R);
      R.Finish;
    finally
      R.Free;
    end;
  except
    T.Free;
    raise;
  end;
  Result := LandrixXmlXPathNodeItem(AddTree(T));
end;

{ a temporary tree: the document node of the body's result }
function TRun.BodyDocument(Body: TObjectList; const Focus: TLandrixXmlXPathFocus;
  const Mode: TXsltMode): TLandrixXmlXPathSequence;
var
  T: TLandrixXmlXPathTree;
  R: TTreeReceiver;
begin
  T := TLandrixXmlXPathTree.Create;
  try
    T.BeginBuild(True);
    R := TTreeReceiver.Create(Self, T, True);
    try
      Exec(Body, Focus, Mode, R);
      R.Finish;
    finally
      R.Free;
    end;
  except
    T.Free;
    raise;
  end;
  Result := LandrixXmlXPathNodeItem(AddTree(T));
end;

{ the simple content of the body's result }
function TRun.BodyString(Body: TObjectList; const Focus: TLandrixXmlXPathFocus;
  const Mode: TXsltMode; const Separator: TLandrixXmlUtf8): TLandrixXmlUtf8;
begin
  Result := SimpleContent(BodySequence(Body, Focus, Mode), Separator);
end;

function TRun.VariableValue(Instr: TXsltInstr; Select: TLandrixXmlXPathExpression; Body: TObjectList;
  HasAs: Boolean; const AsType: TLandrixXmlXPathSequenceType; const Name: TLandrixXmlUtf8;
  const Focus: TLandrixXmlXPathFocus; const Mode: TXsltMode): TLandrixXmlXPathSequence;
begin
  if Select <> nil then
    Result := Eval(Instr, Select, Focus)
  else if HasAs then
    Result := BodySequence(Body, Focus, Mode)
  else if Body.Count = 0 then
    Result := LandrixXmlXPathStringItem('')
  else
    Result := BodyDocument(Body, Focus, Mode);
  if HasAs then
    try
      Result := FEvaluator.ConvertSequence(Result, AsType, '$' + LandrixXmlUtf8ToString(Name));
    except
      on E: ELandrixXmlXPathError do
        if Instr <> nil then
          raise ELandrixXmlXsltError.CreateXslt(xecXslt, E.XPathCode,
            System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), Instr.Module, Instr.Line, Instr.Column)
        else
          raise;
    end;
end;

procedure TRun.Exec(Body: TObjectList; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  I: Integer;
begin
  for I := 0 to Integer(Body.Count) - 1 do
    ExecInstr(TXsltInstr(Body[I]), Focus, Mode, R);
end;

procedure TRun.LiteralElement(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  R: TReceiver);
var
  I: Integer;
  A: TXsltAttributeTemplate;
begin
  R.StartElement(Instr.NamespaceUri, Instr.Prefix, Instr.LocalName);
  for I := 0 to Integer(Length(Instr.NsPrefixes)) - 1 do
    R.NamespaceNode(Instr.NsPrefixes[I], Instr.NsUris[I]);
  for I := 0 to Integer(Instr.Attributes.Count) - 1 do
  begin
    A := TXsltAttributeTemplate(Instr.Attributes[I]);
    R.Attribute(A.NamespaceUri, A.Prefix, A.LocalName, EvalAvt(Instr, A.Value, Focus));
  end;
  Exec(Instr.Body, Focus, Mode, R);
  R.EndElement;
end;

function IsNCName8(const S: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := (S <> '') and not (S[1] in ['0'..'9', '-', '.']);
  for I := 1 to Length(S) do
    if not ((S[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.']) or (Ord(S[I]) >= 128)) then
      Result := False;
end;

procedure TRun.ComputedName(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Element: Boolean;
  out Uri, Prefix, Local: TLandrixXmlUtf8);
var
  Name: TLandrixXmlUtf8;
  I: Integer;
  Found: Boolean;
begin
  Name := EvalAvt(Instr, Instr.NameAvt, Focus);
  I := Pos8(':', Name);
  if I > 0 then
  begin
    Prefix := System.Copy(Name, 1, I - 1);
    Local := System.Copy(Name, I + 1, Length(Name) - I);
  end
  else
  begin
    Prefix := '';
    Local := Name;
  end;
  if not IsNCName8(Local) or ((I > 0) and not IsNCName8(Prefix)) then
  begin
    if Element then
      Fail(Instr, 'XTDE0820', 'not a valid element name: "' + LandrixXmlUtf8ToString(Name) + '"')
    else
      Fail(Instr, 'XTDE0850', 'not a valid attribute name: "' + LandrixXmlUtf8ToString(Name) + '"');
  end;
  if not Element and (Name = 'xmlns') then
    Fail(Instr, 'XTDE0855', 'an attribute cannot be named xmlns');
  if Instr.NamespaceAvt <> nil then
  begin
    Uri := EvalAvt(Instr, Instr.NamespaceAvt, Focus);
    if (Uri = '') then
      Prefix := ''
    else if Uri = LandrixXmlNamespaceXml then
      Prefix := 'xml';
    Exit;
  end;
  { the namespaces in scope at the instruction; the default namespace for
    an element only }
  Uri := '';
  if (Prefix = '') and not Element then
    Exit;
  Found := False;
  for I := 0 to Integer(Length(Instr.ScopePrefixes)) - 1 do
    if Instr.ScopePrefixes[I] = Prefix then
    begin
      Uri := Instr.ScopeUris[I];
      Found := True;
    end;
  if Prefix = 'xml' then
  begin
    Uri := LandrixXmlNamespaceXml;
    Found := True;
  end;
  if not Found and (Prefix <> '') then
  begin
    if Element then
      Fail(Instr, 'XTDE0830', 'the prefix "' + LandrixXmlUtf8ToString(Prefix) + '" is not declared')
    else
      Fail(Instr, 'XTDE0860', 'the prefix "' + LandrixXmlUtf8ToString(Prefix) + '" is not declared');
  end;
end;

procedure TRun.CopyNode(Node: Integer; R: TReceiver);
var
  T: TLandrixXmlXPathTree;
  Base: Integer;

  procedure Walk(I: Integer);
  var
    C, A, K: Integer;
    Prefixes: TLandrixXmlUtf8Array;
    Uri: TLandrixXmlUtf8;
  begin
    Prefixes := nil;
    case T.Kind[I] of
      xnkDocument:
        begin
          C := T.FirstChild(I);
          while C >= 0 do
          begin
            Walk(C);
            C := T.NextSibling[C];
          end;
        end;
      xnkElement:
        begin
          R.StartElement(T.NamespaceUriUtf8(I), T.PrefixUtf8(I), T.LocalNameUtf8(I));
          Prefixes := T.InScopePrefixesUtf8(I);
          for K := 0 to Integer(Length(Prefixes)) - 1 do
            if (Prefixes[K] <> 'xml') and T.LookupNamespace(I, Prefixes[K], Uri) then
              R.NamespaceNode(Prefixes[K], Uri);
          for A := I + 1 to I + T.AttributeCount[I] do
            R.Attribute(T.NamespaceUriUtf8(A), T.PrefixUtf8(A), T.LocalNameUtf8(A), T.ValueUtf8(A));
          C := T.FirstChild(I);
          while C >= 0 do
          begin
            Walk(C);
            C := T.NextSibling[C];
          end;
          R.EndElement;
        end;
      xnkAttribute:
        R.Attribute(T.NamespaceUriUtf8(I), T.PrefixUtf8(I), T.LocalNameUtf8(I), T.ValueUtf8(I));
      xnkText:
        R.Characters(T.ValueUtf8(I));
      xnkComment:
        R.Comment(T.ValueUtf8(I));
      xnkProcessingInstruction:
        R.ProcessingInstruction(T.LocalNameUtf8(I), T.ValueUtf8(I));
    end;
  end;

begin
  T := FEvaluator.TreeOfNode(Node, Base);
  Walk(Node - Base);
end;

{ xsl:copy: a shallow copy of the context item }
procedure TRun.CopyInstr(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  T: TLandrixXmlXPathTree;
  Base, I, K: Integer;
  Prefixes: TLandrixXmlUtf8Array;
  Uri: TLandrixXmlUtf8;
begin
  Prefixes := nil;
  if Focus.Node < 0 then
  begin
    if Focus.Item.Count = 0 then
      Fail(Instr, 'XTTE0945', 'xsl:copy without a context item');
    R.Item(Focus.Item.Items[0], False);
    Exit;
  end;
  T := FEvaluator.TreeOfNode(Focus.Node, Base);
  I := Focus.Node - Base;
  case T.Kind[I] of
    xnkDocument:
      { a document node of its own (an attribute in it is XTDE0420; in a
        tree, its content stays apart from adjacent atomic values) }
      R.Item(BodyDocument(Instr.Body, Focus, Mode).Items[0], False);
    xnkElement:
      begin
        R.StartElement(T.NamespaceUriUtf8(I), T.PrefixUtf8(I), T.LocalNameUtf8(I));
        Prefixes := T.InScopePrefixesUtf8(I);
        for K := 0 to Integer(Length(Prefixes)) - 1 do
          if (Prefixes[K] <> 'xml') and T.LookupNamespace(I, Prefixes[K], Uri) then
            R.NamespaceNode(Prefixes[K], Uri);
        Exec(Instr.Body, Focus, Mode, R);
        R.EndElement;
      end;
  else
    CopyNode(Focus.Node, R);
  end;
end;

function TRun.Supplied(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode): TSuppliedArray;
var
  I: Integer;
  P: TXsltWithParam;
begin
  Result := nil;
  SetLength(Result, Instr.Params.Count);
  for I := 0 to Integer(Instr.Params.Count) - 1 do
  begin
    P := TXsltWithParam(Instr.Params[I]);
    Result[I].Name := P.Name;
    Result[I].Value := VariableValue(Instr, P.Select, P.Body, P.HasAs, P.AsType, P.Name, Focus, Mode);
  end;
end;

function TRun.FindRule(Mode: TXsltMode; Node: Integer): TXsltRule;
var
  T: TLandrixXmlXPathTree;
  Base, I, A, B: Integer;
  Key: string;
  Named: TList;
  Cand: TXsltRule;
  UseNamed: Boolean;

  function Better(X, Y: TXsltRule): Boolean;
  begin
    { X is tried before Y }
    if X.Precedence <> Y.Precedence then
      Result := X.Precedence > Y.Precedence
    else if X.Priority <> Y.Priority then
      Result := X.Priority > Y.Priority
    else
      Result := X.Order > Y.Order;
  end;

begin
  Result := nil;
  T := FEvaluator.TreeOfNode(Node, Base);
  I := Node - Base;
  Named := nil;
  Key := '';
  if T.Kind[I] = xnkElement then
    Key := 'e' + LandrixXmlUtf8ToString(XsltClarkOf(T.NamespaceUriUtf8(I), T.LocalNameUtf8(I)))
  else if T.Kind[I] = xnkAttribute then
    Key := 'a' + LandrixXmlUtf8ToString(XsltClarkOf(T.NamespaceUriUtf8(I), T.LocalNameUtf8(I)));
  if (Key <> '') and Mode.Named.Find(Key, A) then
    Named := TList(Mode.Named.Objects[A]);
  { both lists in the order they are tried: merged }
  A := 0;
  B := 0;
  FEvaluator.CurrentNode := Node;
  FCurrent := LandrixXmlXPathEmpty;
  while True do
  begin
    UseNamed := (Named <> nil) and (A < Named.Count) and
      ((B >= Mode.Others.Count) or Better(TXsltRule(Named[A]), TXsltRule(Mode.Others[B])));
    if not UseNamed and (B >= Mode.Others.Count) then
      Exit;
    if UseNamed then
    begin
      Cand := TXsltRule(Named[A]);
      Inc(A);
    end
    else
    begin
      Cand := TXsltRule(Mode.Others[B]);
      Inc(B);
    end;
    if FEvaluator.MatchesPattern(Cand.Pattern, Node, Cand.Relative) then
    begin
      Result := Cand;
      Exit;
    end;
  end;
end;

{ the parameters of T in the new frame: supplied (converted) or their
  defaults }
procedure TRun.BindParams(T: TXsltTemplate; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  const Params: TSuppliedArray);
var
  I, J: Integer;
  P: TXsltInstr;
  Found: Boolean;
  V: TLandrixXmlXPathSequence;
begin
  for I := 0 to Integer(T.Params.Count) - 1 do
  begin
    P := TXsltInstr(T.Params[I]);
    Found := False;
    for J := 0 to Integer(Length(Params)) - 1 do
      if Params[J].Name = P.VarName then
      begin
        V := Params[J].Value;
        if P.HasAs then
          try
            V := FEvaluator.ConvertSequence(V, P.AsType, '$' + LandrixXmlUtf8ToString(P.VarName));
          except
            on E: ELandrixXmlXPathError do
              raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTTE0590',
                System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), P.Module, P.Line, P.Column);
          end;
        FEvaluator.BindValue(P.Slot, V);
        Found := True;
      end;
    if Found then
      Continue;
    if P.Required then
      raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTDE0700', 'the required parameter ' +
        LandrixXmlUtf8ToString(P.VarName) + ' is not supplied', P.Module, P.Line, P.Column);
    FEvaluator.BindValue(P.Slot, VariableValue(P, P.Select, P.Body, P.HasAs, P.AsType, P.VarName, Focus, Mode));
  end;
end;

{ the body of a template with "as": its result converted }
procedure TRun.TypedBody(T: TXsltTemplate; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  I: Integer;
  V: TLandrixXmlXPathSequence;
  S: TSequenceReceiver;
begin
  S := TSequenceReceiver.Create(Self);
  try
    Exec(T.Body, Focus, Mode, S);
    try
      V := FEvaluator.ConvertSequence(S.Items, T.AsType, 'template ' + LandrixXmlUtf8ToString(T.Name));
    except
      on E: ELandrixXmlXPathError do
        raise ELandrixXmlXsltError.CreateXslt(xecXslt, E.XPathCode,
          System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), T.Module, T.Line, T.Column);
    end;
  finally
    S.Free;
  end;
  for I := 0 to Integer(V.Count) - 1 do
    R.Item(V.Items[I], False);
end;

{ A stylesheet function: its arguments converted to the parameter types
  (XPTY0004, as Saxon reports it), its body run without focus in a frame of its own, the
  result converted to its type (XTTE0780). }
function TRun.CallFunction(T: TXsltTemplate; const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  I, SavedNode: Integer;
  P: TXsltInstr;
  V, SavedCurrent: TLandrixXmlXPathSequence;
  S: TSequenceReceiver;
  SavedGroupActive: Boolean;
begin
  if FTemplateDepth >= FSettings.MaxTemplateDepth then
    raise ELandrixXmlXsltError.CreateXslt(xecLimit, 'FOER0000', 'templates and functions nested deeper than ' +
      IntToStr(FSettings.MaxTemplateDepth), T.Module, T.Line, T.Column);
  Inc(FTemplateDepth);
  { the caller's current() is still needed after the call; there is no
    current group inside a function }
  SavedNode := FEvaluator.CurrentNode;
  SavedCurrent := FCurrent;
  SavedGroupActive := FGroupActive;
  FGroupActive := False;
  FEvaluator.PushFrame(T.FrameSize);
  try
    for I := 0 to Integer(T.Params.Count) - 1 do
    begin
      P := TXsltInstr(T.Params[I]);
      V := LandrixXmlXPathEmpty;
      if I <= High(Args) then
        V := Args[I];
      if P.HasAs then
        try
          V := FEvaluator.ConvertSequence(V, P.AsType, '$' + LandrixXmlUtf8ToString(P.VarName));
        except
          on E: ELandrixXmlXPathError do
            raise ELandrixXmlXsltError.CreateXslt(xecXslt, E.XPathCode,
              System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), P.Module, P.Line, P.Column);
        end;
      FEvaluator.BindValue(P.Slot, V);
    end;
    S := TSequenceReceiver.Create(Self);
    try
      Exec(T.Body, NoFocus, FC.FindMode(''), S);
      Result := S.Items;
    finally
      S.Free;
    end;
    if T.HasAs then
      try
        Result := FEvaluator.ConvertSequence(Result, T.AsType, 'function ' + LandrixXmlUtf8ToString(T.Name));
      except
        on E: ELandrixXmlXPathError do
          raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTTE0780',
            System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), T.Module, T.Line, T.Column);
      end;
  finally
    FEvaluator.PopFrame;
    FEvaluator.CurrentNode := SavedNode;
    FCurrent := SavedCurrent;
    FGroupActive := SavedGroupActive;
    Dec(FTemplateDepth);
  end;
end;

procedure TRun.Invoke(T: TXsltTemplate; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  const Params: TSuppliedArray; R: TReceiver);
begin
  if FTemplateDepth >= FSettings.MaxTemplateDepth then
    raise ELandrixXmlXsltError.CreateXslt(xecLimit, 'FOER0000', 'templates nested deeper than ' +
      IntToStr(FSettings.MaxTemplateDepth), T.Module, T.Line, T.Column);
  Inc(FTemplateDepth);
  FEvaluator.PushFrame(T.FrameSize);
  try
    BindParams(T, Focus, Mode, Params);
    if T.HasAs then
      TypedBody(T, Focus, Mode, R)
    else
      Exec(T.Body, Focus, Mode, R);
  finally
    FEvaluator.PopFrame;
    Dec(FTemplateDepth);
  end;
end;

{ the built-in template rules }
procedure TRun.BuiltIn(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  const Params: TSuppliedArray; R: TReceiver);
var
  T: TLandrixXmlXPathTree;
  Base, C: Integer;
  Children: TLandrixXmlXPathSequence;
begin
  if Focus.Node < 0 then
  begin
    R.Item(Focus.Item.Items[0], False);
    Exit;
  end;
  T := FEvaluator.TreeOfNode(Focus.Node, Base);
  case T.Kind[Focus.Node - Base] of
    xnkDocument, xnkElement:
      begin
        Children := LandrixXmlXPathEmpty;
        C := T.FirstChild(Focus.Node - Base);
        while C >= 0 do
        begin
          LandrixXmlXPathAppend(Children, LandrixXmlXPathNodeItem(C + Base).Items[0]);
          C := T.NextSibling[C];
        end;
        { counted as a template (the depth of a tree is not limited) }
        if FTemplateDepth >= FSettings.MaxTemplateDepth then
        begin
          if Instr = nil then
            raise ELandrixXmlXsltError.CreateXslt(xecLimit, 'FOER0000', 'templates nested deeper than ' +
              IntToStr(FSettings.MaxTemplateDepth), '', 0, 0);
          raise ELandrixXmlXsltError.CreateXslt(xecLimit, 'FOER0000', 'templates nested deeper than ' +
            IntToStr(FSettings.MaxTemplateDepth), Instr.Module, Instr.Line, Instr.Column);
        end;
        Inc(FTemplateDepth);
        try
          ApplyTemplates(Instr, Children, Mode, Params, R);
        finally
          Dec(FTemplateDepth);
        end;
      end;
    xnkText, xnkAttribute:
      R.Characters(T.ValueUtf8(Focus.Node - Base));
  else
    { comments and processing instructions: nothing }
  end;
end;

procedure TRun.ApplyTemplates(Instr: TXsltInstr; const Nodes: TLandrixXmlXPathSequence; Mode: TXsltMode;
  const Params: TSuppliedArray; R: TReceiver);
var
  I: Integer;
  Rule: TXsltRule;
  F: TLandrixXmlXPathFocus;
begin
  Rule := nil;
  for I := 0 to Integer(Nodes.Count) - 1 do
  begin
    F := ItemFocus(Nodes.Items[I], I + 1, Nodes.Count);
    if Nodes.Items[I].Kind <> xikNode then
    begin
      { XSLT 3.0 lets atomic values through the built-in rule; 2.0 errs }
      Fail(Instr, 'XTTE0520', 'xsl:apply-templates selects an atomic value');
    end;
    try
      Rule := FindRule(Mode, Nodes.Items[I].Node);
    except
      on E: ELandrixXmlXsltError do
        raise;
      on E: ELandrixXmlXPathError do
        Located(Instr, E);
    end;
    if Rule = nil then
      BuiltIn(Instr, F, Mode, Params, R)
    else
      Invoke(Rule.Template, F, Mode, Params, R);
  end;
end;

{ raises E again with the instruction's position (if any) }
procedure TRun.Located(Instr: TXsltInstr; E: ELandrixXmlXPathError);
begin
  if Instr = nil then
    raise ELandrixXmlXsltError.CreateXslt(xecXslt, E.XPathCode,
      System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), '', 0, 0);
  raise ELandrixXmlXsltError.CreateXslt(xecXslt, E.XPathCode,
    System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), Instr.Module, Instr.Line, Instr.Column);
end;

procedure TRun.ExecInstr(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
begin
  try
    ExecCore(Instr, Focus, Mode, R);
  except
    on E: ELandrixXmlXsltError do
      raise;
    on E: ELandrixXmlXPathError do
      Located(Instr, E);
  end;
end;

{ One method per instruction: the dispatcher keeps no managed variables
  in its frame, so that deep template recursion needs little stack. }
procedure TRun.DoValueOf(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  Text, Sep: TLandrixXmlUtf8;
begin
  if Instr.Select <> nil then
    Sep := ' '
  else
    Sep := '';
  if Instr.Separator <> nil then
    Sep := EvalAvt(Instr, Instr.Separator, Focus);
  if Instr.Select <> nil then
    Text := EvalString(Instr, Instr.Select, Focus, Sep)
  else
    Text := BodyString(Instr.Body, Focus, Mode, Sep);
  R.Characters(Text);
end;

procedure TRun.DoVariable(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode);
begin
  FEvaluator.BindValue(Instr.Slot, VariableValue(Instr, Instr.Select, Instr.Body, Instr.HasAs, Instr.AsType,
    Instr.VarName, Focus, Mode));
end;

function TRun.Test(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus): Boolean;
begin
  Result := FEvaluator.EffectiveBoolean(Eval(Instr, Instr.Test, Focus));
end;

{ the branch of xsl:choose to run: its body (Instr.Body for otherwise) }
function TRun.ChosenBody(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus): TObjectList;
var
  I: Integer;
  W: TXsltInstr;
begin
  for I := 0 to Integer(Instr.Branches.Count) - 1 do
  begin
    W := TXsltInstr(Instr.Branches[I]);
    if Test(W, Focus) then
    begin
      Result := W.Body;
      Exit;
    end;
  end;
  Result := Instr.Body;
end;

procedure TRun.DoForEach(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  S: TLandrixXmlXPathSequence;
  I: Integer;
begin
  S := Eval(Instr, Instr.Select, Focus);
  for I := 0 to Integer(S.Count) - 1 do
    Exec(Instr.Body, ItemFocus(S.Items[I], I + 1, S.Count), Mode, R);
end;

procedure TRun.DoSequence(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; R: TReceiver);
var
  S: TLandrixXmlXPathSequence;
  I: Integer;
begin
  S := Eval(Instr, Instr.Select, Focus);
  for I := 0 to Integer(S.Count) - 1 do
    R.Item(S.Items[I], Instr.Kind = xskCopyOf);
end;

procedure TRun.DoElement(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  Uri, Prefix, Local: TLandrixXmlUtf8;
begin
  ComputedName(Instr, Focus, True, Uri, Prefix, Local);
  R.StartElement(Uri, Prefix, Local);
  Exec(Instr.Body, Focus, Mode, R);
  R.EndElement;
end;

procedure TRun.DoAttribute(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  Uri, Prefix, Local, Text, Sep: TLandrixXmlUtf8;
begin
  ComputedName(Instr, Focus, False, Uri, Prefix, Local);
  if Instr.Select <> nil then
    Sep := ' '
  else
    Sep := '';
  if Instr.Separator <> nil then
    Sep := EvalAvt(Instr, Instr.Separator, Focus);
  if Instr.Select <> nil then
    Text := EvalString(Instr, Instr.Select, Focus, Sep)
  else
    Text := BodyString(Instr.Body, Focus, Mode, Sep);
  R.Attribute(Uri, Prefix, Local, Text);
end;

{ the text of xsl:comment and xsl:processing-instruction (the separator
  is a space for select and body alike) }
function TRun.InstrText(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode): TLandrixXmlUtf8;
begin
  if Instr.Select <> nil then
    Result := EvalString(Instr, Instr.Select, Focus, ' ')
  else
    Result := BodyString(Instr.Body, Focus, Mode, ' ');
end;

procedure TRun.DoProcessingInstruction(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  R: TReceiver);
var
  Local: TLandrixXmlUtf8;
begin
  Local := EvalAvt(Instr, Instr.NameAvt, Focus);
  if not IsNCName8(Local) or (LowerCase(LandrixXmlUtf8ToString(Local)) = 'xml') then
    Fail(Instr, 'XTDE0890', 'not a valid processing instruction name: "' + LandrixXmlUtf8ToString(Local) + '"');
  R.ProcessingInstruction(Local, PIText(InstrText(Instr, Focus, Mode)));
end;

procedure TRun.DoMessage(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode);
var
  Text, Terminate: TLandrixXmlUtf8;
begin
  Text := FEvaluator.ItemString(ContentDocument(Instr, Focus, Mode).Items[0]);
  Terminate := 'no';
  if Instr.NameAvt <> nil then
    Terminate := EvalAvt(Instr, Instr.NameAvt, Focus);
  FSettings.Messages.Add(TLandrixXmlXsltMessage.Create(Text, Terminate = 'yes', Instr.Module, Instr.Line,
    Instr.Column));
  if Terminate = 'yes' then
    Fail(Instr, 'XTMM9000', 'terminated by xsl:message: ' + LandrixXmlUtf8ToString(Text));
end;

procedure TRun.DoDocument(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
var
  Doc: TLandrixXmlXPathSequence;
begin
  Doc := BodyDocument(Instr.Body, Focus, Mode);
  R.Item(Doc.Items[0], False);
end;

procedure TRun.DoApplyTemplates(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  R: TReceiver);
var
  M: TXsltMode;
  S: TLandrixXmlXPathSequence;
  Params: TSuppliedArray;
begin
  M := TXsltMode(Instr.Mode);
  if Instr.CurrentMode then
    M := Mode;
  S := Eval(Instr, Instr.Select, Focus);
  Params := Supplied(Instr, Focus, Mode);
  ApplyTemplates(Instr, S, M, Params, R);
end;

procedure TRun.DoCallTemplate(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  R: TReceiver);
var
  Params: TSuppliedArray;
begin
  Params := Supplied(Instr, Focus, Mode);
  Invoke(TXsltTemplate(Instr.Template), Focus, Mode, Params, R);
end;

{ Whether Node matches the count pattern (Count) or the from pattern of
  xsl:number; without a count pattern: a node of the kind and name of
  Model. }
function TRun.NumberMatches(Instr: TXsltInstr; Count: Boolean; Node, Model: Integer): Boolean;
var
  I, B, BM: Integer;
  T, TM: TLandrixXmlXPathTree;
begin
  Result := False;
  if Count and (Length(Instr.CountPatterns) = 0) then
  begin
    T := FEvaluator.TreeOfNode(Node, B);
    TM := FEvaluator.TreeOfNode(Model, BM);
    Result := (T.Kind[Node - B] = TM.Kind[Model - BM]) and
      (T.LocalNameUtf8(Node - B) = TM.LocalNameUtf8(Model - BM)) and
      (T.NamespaceUriUtf8(Node - B) = TM.NamespaceUriUtf8(Model - BM));
    Exit;
  end;
  FEvaluator.CurrentNode := Node;
  FCurrent := LandrixXmlXPathEmpty;
  if Count then
  begin
    for I := 0 to Integer(Length(Instr.CountPatterns)) - 1 do
      if FEvaluator.MatchesPattern(Instr.CountPatterns[I], Node, Instr.CountRelative[I]) then
      begin
        Result := True;
        Exit;
      end;
  end
  else
    for I := 0 to Integer(Length(Instr.FromPatterns)) - 1 do
      if FEvaluator.MatchesPattern(Instr.FromPatterns[I], Node, Instr.FromRelative[I]) then
      begin
        Result := True;
        Exit;
      end;
end;

{ The text of one number in a format token: decimal digits (their number
  the minimum width), a, A, i, I. }
function NumberToken(N: Integer; const Token: TLandrixXmlUtf8; const GroupSep: TLandrixXmlUtf8;
  GroupSize: Integer): TLandrixXmlUtf8;
const
  Values: array[0..12] of Integer = (1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1);
  Symbols: array[0..12] of string = ('M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I');
var
  I, K, Width: Integer;
  Digits: Boolean;
  S, Letters: TLandrixXmlUtf8;
begin
  Result := '';
  Letters := 'abcdefghijklmnopqrstuvwxyz';
  if Token = 'A' then
    Letters := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  if (Token = 'a') or (Token = 'A') then
  begin
    K := N;
    while K > 0 do
    begin
      Dec(K);
      Result := Copy(Letters, K mod 26 + 1, 1) + Result;
      K := K div 26;
    end;
    if Result = '' then
      Result := '0';
    Exit;
  end;
  if (Token = 'i') or (Token = 'I') then
  begin
    K := N;
    if (K <= 0) or (K > 9999) then
      Result := LandrixXmlStringToUtf8(IntToStr(K))
    else
      for I := 0 to 12 do
        while K >= Values[I] do
        begin
          Result := Result + LandrixXmlStringToUtf8(Symbols[I]);
          Dec(K, Values[I]);
        end;
    if Token = 'i' then
      Result := LandrixXmlStringToUtf8(LowerCase(LandrixXmlUtf8ToString(Result)));
    Exit;
  end;
  Digits := Token <> '';
  for I := 1 to Length(Token) do
    if not (Token[I] in ['0'..'9']) then
      Digits := False;
  if not Digits then
    raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT: the xsl:number format token "' +
      LandrixXmlUtf8ToString(Token) + '" is not supported');
  Width := Length(Token);
  Result := LandrixXmlStringToUtf8(IntToStr(N));
  while Length(Result) < Width do
    Result := '0' + Result;
  if (GroupSep <> '') and (GroupSize > 0) then
  begin
    S := '';
    K := 0;
    for I := Length(Result) downto 1 do
    begin
      if (K > 0) and (K mod GroupSize = 0) then
        S := GroupSep + S;
      S := Copy(Result, I, 1) + S;
      Inc(K);
    end;
    Result := S;
  end;
end;

{ Numbers formatted as XSLT 2.0 12.3 says: the alphanumeric tokens of the
  format and the separators between them (prefix and suffix kept; the
  last token and separator for further numbers). }
function FormatNumbers(const Numbers: array of Integer; const Format, GroupSep: TLandrixXmlUtf8;
  GroupSize: Integer): TLandrixXmlUtf8;
var
  Tokens, Seps: TLandrixXmlUtf8Array;
  Prefix, Suffix, Sep, Token: TLandrixXmlUtf8;
  I, Start, K: Integer;

  function Alnum(C: AnsiChar): Boolean;
  begin
    Result := C in ['0'..'9', 'A'..'Z', 'a'..'z'];
  end;

begin
  Tokens := nil;
  Seps := nil;
  Prefix := '';
  Suffix := '';
  for I := 1 to Length(Format) do
    if Ord(Format[I]) >= $80 then
      raise ELandrixXmlError.CreateCode(xecUnsupported, 'XSLT: an xsl:number format with characters ' +
        'other than ASCII is not supported');
  I := 1;
  while (I <= Length(Format)) and not Alnum(Format[I]) do
    Inc(I);
  Prefix := Copy(Format, 1, I - 1);
  while I <= Length(Format) do
  begin
    Start := I;
    while (I <= Length(Format)) and Alnum(Format[I]) do
      Inc(I);
    K := Integer(Length(Tokens));
    SetLength(Tokens, K + 1);
    Tokens[K] := Copy(Format, Start, I - Start);
    Start := I;
    while (I <= Length(Format)) and not Alnum(Format[I]) do
      Inc(I);
    if I > Length(Format) then
      Suffix := Copy(Format, Start, I - Start)
    else
    begin
      SetLength(Seps, K + 1);
      Seps[K] := Copy(Format, Start, I - Start);
    end;
  end;
  if Length(Tokens) = 0 then
  begin
    { no token: "1", the format before and after it }
    SetLength(Tokens, 1);
    Tokens[0] := '1';
    Suffix := Prefix;
  end;
  Result := Prefix;
  for I := 0 to Integer(High(Numbers)) do
  begin
    if I > 0 then
    begin
      if I - 1 < Length(Seps) then
        Sep := Seps[I - 1]
      else if Length(Seps) > 0 then
        Sep := Seps[High(Seps)]
      else
        Sep := '.';
      Result := Result + Sep;
    end;
    if I < Length(Tokens) then
      Token := Tokens[I]
    else
      Token := Tokens[High(Tokens)];
    Result := Result + NumberToken(Numbers[I], Token, GroupSep, GroupSize);
  end;
  Result := Result + Suffix;
end;

procedure TRun.DoNumber(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; R: TReceiver);
var
  Numbers: array of Integer;
  S: TLandrixXmlXPathSequence;
  T: TLandrixXmlXPathTree;
  Node, B, I, A, C, K: Integer;
  GroupSep, V: TLandrixXmlUtf8;
  GroupSize: Integer;
  Chain: array of Integer;

  procedure Add(N: Integer);
  begin
    SetLength(Numbers, Length(Numbers) + 1);
    Numbers[High(Numbers)] := N;
  end;

  { 1 + the preceding siblings of Node that match the count pattern }
  function SiblingNumber(N: Integer): Integer;
  var
    P, X: Integer;
  begin
    Result := 1;
    if T.Kind[N - B] = xnkAttribute then
      Exit;
    P := T.Parent[N - B];
    if P < 0 then
      Exit;
    X := T.FirstChild(P);
    while (X >= 0) and (X <> N - B) do
    begin
      if NumberMatches(Instr, True, X + B, Node) then
        Inc(Result);
      X := T.NextSibling[X];
    end;
  end;

begin
  Numbers := nil;
  Chain := nil;
  if Instr.NumberValue <> nil then
  begin
    S := Eval(Instr, Instr.NumberValue, Focus);
    for I := 0 to Integer(S.Count) - 1 do
    begin
      { round(number(.)), -1 for NaN }
      K := StrToIntDef(LandrixXmlUtf8ToString(FEvaluator.ItemString(FEvaluator.EvaluateInFocus(FRoundExpr,
        ItemFocus(S.Items[I], 1, 1)).Items[0])), -1);
      if K = -2 then
        raise ELandrixXmlXsltError.CreateXslt(xecUnsupported, 'FOER0000', 'xsl:number: a value above ' +
          IntToStr(MaxInt) + ' is not supported', Instr.Module, Instr.Line, Instr.Column);
      if K < 0 then
        Fail(Instr, 'XTDE0980', 'xsl:number: ' + LandrixXmlUtf8ToString(FEvaluator.ItemString(S.Items[I])) +
          ' is no number from 0 on');
      Add(K);
    end;
  end
  else
  begin
    if Instr.Select <> nil then
    begin
      S := Eval(Instr, Instr.Select, Focus);
      if (S.Count <> 1) or (S.Items[0].Kind <> xikNode) then
        Fail(Instr, 'XTTE1000', 'xsl:number: select must give one node');
      Node := S.Items[0].Node;
    end
    else
    begin
      if Focus.Node < 0 then
        Fail(Instr, 'XTTE0990', 'xsl:number: the context item is no node');
      Node := Focus.Node;
    end;
    T := FEvaluator.TreeOfNode(Node, B);
    case Instr.NumberLevel of
      0, 1:
        begin
          { the ancestors-or-self that match count, up to one that matches from }
          A := Node - B;
          while A >= 0 do
          begin
            if NumberMatches(Instr, True, A + B, Node) then
            begin
              SetLength(Chain, Length(Chain) + 1);
              Chain[High(Chain)] := A + B;
              if Instr.NumberLevel = 0 then
                Break;
            end;
            if (Length(Instr.FromPatterns) > 0) and NumberMatches(Instr, False, A + B, Node) then
              Break;
            A := T.Parent[A];
          end;
          for I := Integer(High(Chain)) downto 0 do
            Add(SiblingNumber(Chain[I]));
        end;
    else
      begin
        { the nodes before Node (not attributes) and its ancestors-or-self
          that match count, after the last one that matches from }
        C := 0;
        for K := 0 to Node - B do
        begin
          if (T.Kind[K] = xnkAttribute) and (K <> Node - B) then
            Continue;
          if (Length(Instr.FromPatterns) > 0) and NumberMatches(Instr, False, K + B, Node) then
            C := 0;
          if NumberMatches(Instr, True, K + B, Node) then
            Inc(C);
        end;
        if C > 0 then
          Add(C);
      end;
    end;
  end;
  GroupSep := '';
  GroupSize := 0;
  if (Instr.GroupingSeparator <> nil) and (Instr.GroupingSize <> nil) then
  begin
    GroupSep := EvalAvt(Instr, Instr.GroupingSeparator, Focus);
    { an integer; 0 or less: no grouping (as Saxon) }
    V := EvalAvt(Instr, Instr.GroupingSize, Focus);
    A := 1;
    if (V <> '') and (V[1] = '-') then
      A := 2;
    if A > Length(V) then
      Fail(Instr, 'XTDE0030', 'xsl:number: grouping-size must be an integer');
    GroupSize := 0;
    for I := A to Length(V) do
      if not (V[I] in ['0'..'9']) then
        Fail(Instr, 'XTDE0030', 'xsl:number: grouping-size must be an integer')
      else if GroupSize < 100000 then
        GroupSize := GroupSize * 10 + Ord(V[I]) - Ord('0');
    if A = 2 then
      GroupSize := 0;
  end;
  R.Characters(FormatNumbers(Numbers, EvalAvt(Instr, Instr.FormatAvt, Focus), GroupSep, GroupSize));
end;

{ format-number(value, picture[, name]): the value as a function argument
  of type xs:numeric? (an untyped value or node as xs:double, the empty
  sequence as NaN), the decimal format by name (XTDE1280) }
function TRun.FormatNumber(const Args: array of TLandrixXmlXPathSequence): TLandrixXmlXPathSequence;
var
  Value, Picture, Name: TLandrixXmlUtf8;
  It: TLandrixXmlXPathItem;
  K, Scale: Integer;
  Scaled: Boolean;
begin
  Picture := FEvaluator.ItemString(FEvaluator.ConvertSequence(Args[1], FStringType, 'format-number()').Items[0]);
  Name := '';
  if High(Args) >= 2 then
    Name := LandrixXmlStringToUtf8(Trim(LandrixXmlUtf8ToString(FEvaluator.ItemString(
      FEvaluator.ConvertSequence(Args[2], FStringType, 'format-number()').Items[0]))));
  K := FC.DecimalFormats.IndexOf(LandrixXmlUtf8ToString(Name));
  if K < 0 then
    raise ELandrixXmlXPathError.CreateXPath('FODF1280', 'format-number(): there is no decimal format ' +
      LandrixXmlUtf8ToString(Name));
  if Args[0].Count = 0 then
    Value := 'NaN'
  else
  begin
    if Args[0].Count > 1 then
      raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'format-number(): the value must be one number');
    It := Args[0].Items[0];
    case It.Kind of
      xikInteger, xikDecimal, xikDouble, xikNonPositiveInteger, xikNegativeInteger, xikLong, xikInt,
      xikShort, xikByte, xikNonNegativeInteger, xikUnsignedLong, xikUnsignedInt, xikUnsignedShort,
      xikUnsignedByte, xikPositiveInteger:
        Value := FEvaluator.ItemString(It);
      xikFloat, xikUntypedAtomic, xikNode:
        { a float widened to xs:double, an untyped value cast }
        begin
          It := FEvaluator.EvaluateInFocus(FDoubleExpr, ItemFocus(It, 1, 1)).Items[0];
          Value := FEvaluator.ItemString(It);
        end;
    else
      raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'format-number(): the value must be a number');
    end;
  end;
  { a double in a picture with percent or per mille: multiplied as a double
    (Saxon: 0.545 is 55%) }
  Scaled := False;
  if (Args[0].Count > 0) and (It.Kind = xikDouble) then
  begin
    Scale := XsltPictureScale(Picture, TXsltDecimalFormat(FC.DecimalFormats.Objects[K]),
      (Value <> '') and (Value[1] = '-'));
    if Scale > 1 then
    begin
      if Scale = 100 then
        Value := FEvaluator.ItemString(FEvaluator.EvaluateInFocus(FTimes100Expr, ItemFocus(It, 1, 1)).Items[0])
      else
        Value := FEvaluator.ItemString(FEvaluator.EvaluateInFocus(FTimes1000Expr, ItemFocus(It, 1, 1)).Items[0]);
      Scaled := True;
    end;
  end;
  Result := LandrixXmlXPathStringItem(XsltFormatNumber(Value, Picture,
    TXsltDecimalFormat(FC.DecimalFormats.Objects[K]), Scaled));
end;

{ The value an atomic item (or a node: its string value) is compared by
  in grouping and key(): strings and untyped values as strings, numbers
  as xs:double (NaN equal to NaN), other types by their type and value. }
function TRun.AtomKey(const It: TLandrixXmlXPathItem): TLandrixXmlUtf8;
begin
  case It.Kind of
    xikNode, xikUntypedAtomic, xikString, xikAnyUri, xikNormalizedString, xikToken, xikLanguage, xikNMTOKEN,
    xikName, xikNCName, xikID, xikIDREF, xikENTITY:
      Result := 's' + FEvaluator.ItemString(It);
    xikInteger, xikDecimal, xikDouble, xikFloat, xikNonPositiveInteger, xikNegativeInteger, xikLong, xikInt,
    xikShort, xikByte, xikNonNegativeInteger, xikUnsignedLong, xikUnsignedInt, xikUnsignedShort,
    xikUnsignedByte, xikPositiveInteger:
      begin
        Result := 'n' + FEvaluator.ItemString(FEvaluator.EvaluateInFocus(FNumberExpr, ItemFocus(It, 1, 1)).Items[0]);
        if Result = 'n-0' then
          Result := 'n0';
      end;
    xikBoolean:
      Result := 'b' + FEvaluator.ItemString(It);
    xikQName, xikDateTime, xikTime:
      Result := 'o' + LandrixXmlStringToUtf8(IntToStr(Ord(It.Kind))) + ':' +
        FEvaluator.ItemString(FEvaluator.EvaluateInFocus(FKeyNormExpr, ItemFocus(It, 1, 1)).Items[0]);
  else
    Result := 'o' + LandrixXmlStringToUtf8(IntToStr(Ord(It.Kind))) + ':' + FEvaluator.ItemString(It);
  end;
end;

{ An id as Saxon makes them: "d", the number of the tree, then a letter
  for the kind (e element, t text, c comment, p processing instruction)
  and the number of the node among the nodes that are no attributes; an
  attribute: its element's id, "a" and its position. }
function TRun.GenerateId(Node: Integer): TLandrixXmlUtf8;
var
  T: TLandrixXmlXPathTree;
  B, I, J, K, Owner: Integer;
begin
  T := FEvaluator.TreeOfNode(Node, B);
  Result := 'd' + LandrixXmlStringToUtf8(IntToStr(FEvaluator.TreeNumber(Node) + 1));
  I := Node - B;
  Owner := I;
  if T.Kind[I] = xnkAttribute then
    Owner := T.Parent[I];
  if T.Kind[Owner] = xnkDocument then
    Exit;
  { the numbers of the nodes that are no attributes, counted once per tree }
  if (FIdTree <> T) or (Length(FIdNumbers) <> T.Count) then
  begin
    FIdTree := T;
    SetLength(FIdNumbers, T.Count);
    K := 0;
    if T.Kind[0] <> xnkDocument then
      K := 1;
    for J := 0 to T.Count - 1 do
    begin
      FIdNumbers[J] := K;
      if T.Kind[J] <> xnkAttribute then
        Inc(K);
    end;
  end;
  K := FIdNumbers[Owner];
  case T.Kind[Owner] of
    xnkElement: Result := Result + 'e';
    xnkText: Result := Result + 't';
    xnkComment: Result := Result + 'c';
  else
    Result := Result + 'p';
  end;
  Result := Result + LandrixXmlStringToUtf8(IntToStr(K));
  if Owner <> I then
    Result := Result + 'a' + LandrixXmlStringToUtf8(IntToStr(I - Owner));
end;

{ The index of key K in the tree whose root is Root, built on first use:
  every node that matches a declaration's pattern under each value of its
  use expression. }
function TRun.KeyIndex(K: TXsltKey; Root: Integer): TObject;
var
  Index: TKeyIndex;
  T: TLandrixXmlXPathTree;
  B, I, J, D, P: Integer;
  Decl: TXsltKeyDecl;
  V: TLandrixXmlXPathSequence;
  Value: string;
  Nodes: TKeyNodes;
  SavedNode: Integer;
  SavedCurrent: TLandrixXmlXPathSequence;
  Matched: Boolean;
begin
  for I := 0 to Integer(FKeyIndexes.Count) - 1 do
  begin
    Index := TKeyIndex(FKeyIndexes[I]);
    if (Index.Key = K) and (Index.Root = Root) then
    begin
      if Index.Building then
        raise ELandrixXmlXPathError.CreateXPath('XTDE0640', 'the key ' + LandrixXmlUtf8ToString(K.Name) +
          ' is used to build itself');
      Result := Index;
      Exit;
    end;
  end;
  Index := TKeyIndex.Create;
  FKeyIndexes.Add(Index);
  Index.Key := K;
  Index.Root := Root;
  Index.Building := True;
  Result := Index;
  T := FEvaluator.TreeOfNode(Root, B);
  SavedNode := FEvaluator.CurrentNode;
  SavedCurrent := FCurrent;
  try
    for I := 0 to T.Count - 1 do
      for D := 0 to Integer(K.Decls.Count) - 1 do
      begin
        Decl := TXsltKeyDecl(K.Decls[D]);
        { current() in the pattern and the use expression is the node }
        FEvaluator.CurrentNode := I + B;
        FCurrent := LandrixXmlXPathEmpty;
        Matched := False;
        for P := 0 to Integer(Length(Decl.Patterns)) - 1 do
          if FEvaluator.MatchesPattern(Decl.Patterns[P], I + B, Decl.Relative[P]) then
          begin
            Matched := True;
            Break;
          end;
        if not Matched then
          Continue;
        V := FEvaluator.EvaluateInFocus(Decl.Use, NodeFocus(I + B, 1, 1));
        for J := 0 to Integer(V.Count) - 1 do
        begin
          Value := LandrixXmlUtf8ToString(AtomKey(V.Items[J]));
          { NaN is equal to no value }
          if Value = 'nNaN' then
            Continue;
          P := Index.Map.IndexOf(Value);
          if P >= 0 then
            Nodes := TKeyNodes(Index.Map.Objects[P])
          else
          begin
            Nodes := TKeyNodes.Create;
            Index.Map.AddObject(Value, Nodes);
          end;
          Nodes.Add(I + B);
        end;
      end;
    Index.Building := False;
  except
    { not kept half built }
    FKeyIndexes.Delete(Integer(FKeyIndexes.IndexOf(Index)));
    FEvaluator.CurrentNode := SavedNode;
    FCurrent := SavedCurrent;
    raise;
  end;
  FEvaluator.CurrentNode := SavedNode;
  FCurrent := SavedCurrent;
end;

{ key(name, values[, top]): the nodes of the tree of top (the context
  node) that have one of the values under the key, inside top, in
  document order }
function TRun.KeyFunction(const Args: array of TLandrixXmlXPathSequence;
  const Focus: TLandrixXmlXPathFocus): TLandrixXmlXPathSequence;
var
  Name: TLandrixXmlUtf8;
  I, J, Top, Root, B, N, X: Integer;
  K: TXsltKey;
  Index: TKeyIndex;
  T: TLandrixXmlXPathTree;
  Found: array of Integer;
  Count: Integer;
  Nodes: TKeyNodes;
  Inside: Boolean;
begin
  Result := LandrixXmlXPathEmpty;
  Found := nil;
  if (Args[0].Count <> 1) then
    raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'key(): the name must be one string');
  Name := LandrixXmlStringToUtf8(Trim(LandrixXmlUtf8ToString(FEvaluator.ItemString(Args[0].Items[0]))));
  I := FC.Keys.IndexOf(LandrixXmlUtf8ToString(Name));
  if I < 0 then
    raise ELandrixXmlXPathError.CreateXPath('XTDE1260', 'key(): there is no key ' + LandrixXmlUtf8ToString(Name));
  K := TXsltKey(FC.Keys.Objects[I]);
  if High(Args) >= 2 then
  begin
    if (Args[2].Count <> 1) or (Args[2].Items[0].Kind <> xikNode) then
      raise ELandrixXmlXPathError.CreateXPath('XPTY0004', 'key(): the third argument must be one node');
    Top := Args[2].Items[0].Node;
  end
  else
  begin
    if Focus.Node < 0 then
      raise ELandrixXmlXPathError.CreateXPath('XTDE1270', 'key(): the context item is no node');
    Top := Focus.Node;
  end;
  T := FEvaluator.TreeOfNode(Top, B);
  Root := Top - B;
  while T.Parent[Root] >= 0 do
    Root := T.Parent[Root];
  { two arguments: the whole document of the context node }
  if High(Args) < 2 then
    Top := Root + B;
  if T.Kind[Root] <> xnkDocument then
    raise ELandrixXmlXPathError.CreateXPath('XTDE1270', 'key(): the node is not in a document');
  Index := TKeyIndex(KeyIndex(K, Root + B));
  Count := 0;
  for I := 0 to Integer(Args[1].Count) - 1 do
  begin
    J := Index.Map.IndexOf(LandrixXmlUtf8ToString(AtomKey(Args[1].Items[I])));
    if J < 0 then
      Continue;
    Nodes := TKeyNodes(Index.Map.Objects[J]);
    for N := 0 to Nodes.Count - 1 do
    begin
      { inside Top (its descendants or itself) }
      X := Nodes.Nodes[N] - B;
      Inside := Top = Root + B;
      while not Inside and (X >= 0) do
      begin
        Inside := X + B = Top;
        X := T.Parent[X];
      end;
      if not Inside then
        Continue;
      if Count = Length(Found) then
        SetLength(Found, 2 * Count + 8);
      Found[Count] := Nodes.Nodes[N];
      Inc(Count);
    end;
  end;
  { document order, each node once }
  for I := 1 to Count - 1 do
  begin
    N := Found[I];
    J := I - 1;
    while (J >= 0) and (Found[J] > N) do
    begin
      Found[J + 1] := Found[J];
      Dec(J);
    end;
    Found[J + 1] := N;
  end;
  for I := 0 to Count - 1 do
    if (I = 0) or (Found[I] <> Found[I - 1]) then
      LandrixXmlXPathAppend(Result, LandrixXmlXPathNodeItem(Found[I]).Items[0]);
end;

{ xsl:for-each-group: the groups in the order of their first item, the
  body once per group with its first item as context item }
procedure TRun.DoForEachGroup(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode;
  R: TReceiver);
var
  Population, Keys: TLandrixXmlXPathSequence;
  Groups, GroupKeys: array of TLandrixXmlXPathSequence;
  Map: TXsltStringList;
  I, J, G, P, Count: Integer;
  Key, Previous: TLandrixXmlUtf8;
  Seen: string;
  Starts, Matched: Boolean;
  SavedGroup, SavedKey: TLandrixXmlXPathSequence;
  SavedActive, SavedHasKey: Boolean;
  SavedLazy: Integer;
  Box: TKeyNodes;

  { an atomic key: a node as its string value }
  function Atomic(const It: TLandrixXmlXPathItem): TLandrixXmlXPathItem;
  begin
    Result := It;
    if It.Kind = xikNode then
    begin
      Result.Kind := xikUntypedAtomic;
      Result.Text := FEvaluator.ItemString(It);
      Result.Node := -1;
      Result.Bits := 0;
      Result.Payload := nil;
    end;
  end;

  procedure NewGroup(const It: TLandrixXmlXPathItem; const K: TLandrixXmlXPathSequence);
  begin
    SetLength(Groups, Count + 1);
    SetLength(GroupKeys, Count + 1);
    Groups[Count] := LandrixXmlXPathEmpty;
    LandrixXmlXPathAppend(Groups[Count], It);
    GroupKeys[Count] := K;
    Inc(Count);
  end;

begin
  Groups := nil;
  GroupKeys := nil;
  Count := 0;
  Population := Eval(Instr, Instr.Select, Focus);
  Map := TXsltStringList.Create;
  try
    Map.CaseSensitive := True;
    Map.Sorted := True;
    Previous := '';
    for I := 0 to Integer(Population.Count) - 1 do
      case Instr.GroupKind of
        0:
          begin
            Keys := Eval(Instr, Instr.Test, ItemFocus(Population.Items[I], I + 1, Population.Count));
            Seen := #1;
            for J := 0 to Integer(Keys.Count) - 1 do
            begin
              Key := AtomKey(Keys.Items[J]);
              { an item in a group once, even with two equal keys }
              if Pos(#1 + LandrixXmlUtf8ToString(Key) + #1, Seen) > 0 then
                Continue;
              Seen := Seen + LandrixXmlUtf8ToString(Key) + #1;
              if Map.Find(LandrixXmlUtf8ToString(Key), G) then
                LandrixXmlXPathAppend(Groups[TKeyNodes(Map.Objects[G]).Nodes[0]], Population.Items[I])
              else
              begin
                { the group's number (in a TKeyNodes, freed with the map) }
                Box := TKeyNodes.Create;
                Box.Add(Count);
                Map.AddObject(LandrixXmlUtf8ToString(Key), Box);
                NewGroup(Population.Items[I], LandrixXmlXPathEmpty);
                LandrixXmlXPathAppend(GroupKeys[Count - 1], Atomic(Keys.Items[J]));
              end;
            end;
          end;
        1:
          begin
            Keys := Eval(Instr, Instr.Test, ItemFocus(Population.Items[I], I + 1, Population.Count));
            if Keys.Count <> 1 then
              Fail(Instr, 'XTTE1100', 'xsl:for-each-group: group-adjacent must give one value');
            Key := AtomKey(Keys.Items[0]);
            if (Count > 0) and (Key = Previous) then
              LandrixXmlXPathAppend(Groups[Count - 1], Population.Items[I])
            else
            begin
              NewGroup(Population.Items[I], LandrixXmlXPathEmpty);
              LandrixXmlXPathAppend(GroupKeys[Count - 1], Atomic(Keys.Items[0]));
            end;
            Previous := Key;
          end;
      else
        begin
          if Population.Items[I].Kind <> xikNode then
            Fail(Instr, 'XTTE1120', 'xsl:for-each-group: a pattern needs nodes to group');
          FEvaluator.CurrentNode := Population.Items[I].Node;
          FCurrent := LandrixXmlXPathEmpty;
          Matched := False;
          for P := 0 to Integer(Length(Instr.CountPatterns)) - 1 do
            if FEvaluator.MatchesPattern(Instr.CountPatterns[P], Population.Items[I].Node, Instr.CountRelative[P]) then
            begin
              Matched := True;
              Break;
            end;
          if Instr.GroupKind = 2 then
            Starts := (Count = 0) or Matched
          else
            Starts := (Count = 0) or (Previous = 'end');
          if Starts then
            NewGroup(Population.Items[I], LandrixXmlXPathEmpty)
          else
            LandrixXmlXPathAppend(Groups[Count - 1], Population.Items[I]);
          if Matched then
            Previous := 'end'
          else
            Previous := '';
        end;
      end;
  finally
    for G := 0 to Integer(Map.Count) - 1 do
      Map.Objects[G].Free;
    Map.Free;
  end;
  SavedGroup := FGroup;
  SavedKey := FGroupKey;
  SavedActive := FGroupActive;
  SavedLazy := FGroupLazyDepth;
  SavedHasKey := FGroupHasKey;
  try
    for G := 0 to Count - 1 do
    begin
      FGroup := Groups[G];
      FGroupKey := GroupKeys[G];
      FGroupActive := True;
      FGroupHasKey := Instr.GroupKind <= 1;
      FGroupLazyDepth := FEvaluator.LazyDepth;
      Exec(Instr.Body, ItemFocus(Groups[G].Items[0], G + 1, Count), Mode, R);
    end;
  finally
    FGroup := SavedGroup;
    FGroupKey := SavedKey;
    FGroupActive := SavedActive;
    FGroupLazyDepth := SavedLazy;
    FGroupHasKey := SavedHasKey;
  end;
end;

procedure TRun.ExecCore(Instr: TXsltInstr; const Focus: TLandrixXmlXPathFocus; Mode: TXsltMode; R: TReceiver);
begin
  case Instr.Kind of
    xskText:
      R.Characters(Instr.Text);
    xskLiteralElement:
      LiteralElement(Instr, Focus, Mode, R);
    xskValueOf:
      DoValueOf(Instr, Focus, Mode, R);
    xskVariable:
      DoVariable(Instr, Focus, Mode);
    xskIf:
      if Test(Instr, Focus) then
        Exec(Instr.Body, Focus, Mode, R);
    xskChoose:
      Exec(ChosenBody(Instr, Focus), Focus, Mode, R);
    xskForEach:
      DoForEach(Instr, Focus, Mode, R);
    xskSequence, xskCopyOf:
      DoSequence(Instr, Focus, R);
    xskCopy:
      CopyInstr(Instr, Focus, Mode, R);
    xskElement:
      DoElement(Instr, Focus, Mode, R);
    xskAttribute:
      DoAttribute(Instr, Focus, Mode, R);
    xskComment:
      R.Comment(CommentText(InstrText(Instr, Focus, Mode)));
    xskProcessingInstruction:
      DoProcessingInstruction(Instr, Focus, Mode, R);
    xskMessage:
      DoMessage(Instr, Focus, Mode);
    xskDocument:
      DoDocument(Instr, Focus, Mode, R);
    xskApplyTemplates:
      DoApplyTemplates(Instr, Focus, Mode, R);
    xskCallTemplate:
      DoCallTemplate(Instr, Focus, Mode, R);
    xskNumber:
      DoNumber(Instr, Focus, R);
    xskForEachGroup:
      DoForEachGroup(Instr, Focus, Mode, R);
  else
    { xsl:when and xsl:namespace are not compiled as instructions of
      their own }
  end;
end;

procedure TRun.BindGlobals;
var
  I, J: Integer;
  G: TXsltGlobal;
  Found: Boolean;
  V: TLandrixXmlXPathSequence;
  It: TLandrixXmlXPathItem;
  X: TLandrixXmlXPathExpression;
  Ctx: TLandrixXmlXPathStaticContext;
  Root: Integer;
begin
  FEvaluator.SetGlobalCount(FC.GlobalCount);
  { the context item of the globals: the source's document node, none
    without a source (a use of the context is XPDY0002) }
  Root := 0;
  if FEmpty <> nil then
    Root := -1;
  for I := 0 to Integer(FC.Globals.Count) - 1 do
  begin
    G := TXsltGlobal(FC.Globals[I]);
    Found := False;
    if G.IsParam then
      for J := 0 to Integer(Length(FSettings.ParamNames)) - 1 do
        if FSettings.ParamNames[J] = G.Name then
        begin
          Found := True;
          case FSettings.ParamKinds[J] of
            0:
              begin
                It.Kind := xikUntypedAtomic;
                It.Node := -1;
                It.Bits := 0;
                It.Text := FSettings.ParamValues[J];
                It.Payload := nil;
                V := LandrixXmlXPathEmpty;
                LandrixXmlXPathAppend(V, It);
              end;
            1:
              if FSettings.ParamTrees[J] = FSource then
                V := LandrixXmlXPathNodeItem(0)
              else
                V := LandrixXmlXPathNodeItem(FEvaluator.AddTree(FSettings.ParamTrees[J]));
          else
            begin
              Ctx := TLandrixXmlXPathStaticContext.Create;
              try
                Ctx.Profile := xppSaxon;
                X := TLandrixXmlXPathExpression.Create(FSettings.ParamValues[J], Ctx);
              finally
                Ctx.Free;
              end;
              FParamExprs.Add(X);
              V := FEvaluator.EvaluateInFocus(X, NoFocus);
            end;
          end;
          if G.HasAs then
            try
              V := FEvaluator.ConvertSequence(V, G.AsType, '$' + LandrixXmlUtf8ToString(G.Name));
            except
              on E: ELandrixXmlXPathError do
                raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTTE0590',
                  System.Copy(E.Message, Length(E.XPathCode) + 3, MaxInt), G.Module, G.Line, G.Column);
            end;
          FEvaluator.BindValue(G.Slot, V);
        end;
    if Found then
      Continue;
    if G.Required then
      raise ELandrixXmlXsltError.CreateXslt(xecXslt, 'XTDE0050', 'the required parameter ' +
        LandrixXmlUtf8ToString(G.Name) + ' is not supplied', G.Module, G.Line, G.Column);
    if G.Select <> nil then
    begin
      if G.HasAs then
        FEvaluator.BindLazyAs(G.Slot, G.Select, Root, G.AsType)
      else
        FEvaluator.BindLazy(G.Slot, G.Select, Root);
    end
    else if G.Call <> nil then
      FEvaluator.BindLazy(G.Slot, G.Call, Root)
    else if G.HasAs then
      FEvaluator.BindValue(G.Slot, FEvaluator.ConvertSequence(LandrixXmlXPathEmpty, G.AsType,
        '$' + LandrixXmlUtf8ToString(G.Name)))
    else
      FEvaluator.BindValue(G.Slot, LandrixXmlXPathStringItem(''));
  end;
end;

procedure TRun.Start(Target: TLandrixXmlXPathTree);
var
  R: TTreeReceiver;
  Mode: TXsltMode;
  T: TXsltTemplate;
  I: Integer;
  Params: TSuppliedArray;
begin
  BindGlobals;
  Params := nil;
  Target.BeginBuild(True);
  R := TTreeReceiver.Create(Self, Target, True);
  try
    if FSettings.InitialTemplate <> '' then
    begin
      if not FC.NamedTemplates.Find(LandrixXmlUtf8ToString(FSettings.InitialTemplate), I) then
        Fail(nil, 'XTDE0040', 'no template named ' + LandrixXmlUtf8ToString(FSettings.InitialTemplate));
      T := TXsltTemplate(FC.NamedTemplates.Objects[I]);
      Mode := FC.FindMode(FSettings.InitialMode);
      if Mode = nil then
        Mode := FC.FindMode('');
      if FEmpty = nil then
        Invoke(T, NodeFocus(0, 1, 1), Mode, Params, R)
      else
        Invoke(T, NoFocus, Mode, Params, R);
    end
    else
    begin
      if FEmpty <> nil then
        Fail(nil, 'XTDE0040', 'neither a source document nor an initial template');
      Mode := FC.FindMode(FSettings.InitialMode);
      if Mode = nil then
        Fail(nil, 'XTDE0045', 'the stylesheet has no mode ' + LandrixXmlUtf8ToString(FSettings.InitialMode));
      ApplyTemplates(nil, LandrixXmlXPathNodeItem(0), Mode, Params, R);
    end;
    R.Finish;
  finally
    R.Free;
  end;
end;

procedure XsltRun(Compiled: TObject; Settings: TXsltRunSettings; Source, Target: TLandrixXmlXPathTree);
var
  Run: TRun;
begin
  Run := TRun.Create(TXsltCompiled(Compiled), Settings, Source);
  try
    Run.Start(Target);
  finally
    Run.Free;
  end;
end;

end.
