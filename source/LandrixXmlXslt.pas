{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  XSLT 2.0 transformations: the subset the KoSIT report and visualization
  stylesheets use, run as Saxon HE runs them (XPath in the Saxon profile
  of LandrixXmlXPathEval). Constructs outside the subset are rejected
  when the stylesheet is loaded (xecUnsupported).

  TLandrixXmlXsltStylesheet is the compiled stylesheet: loaded once,
  immutable afterwards, shareable between threads. A
  TLandrixXmlXsltTransformer runs it, one run at a time; its parameters
  stay set across runs. Names of parameters, modes and templates are
  written in Clark notation (the namespace URI in curly brackets, then
  the local name), or as an NCName for no
  namespace.

  Errors raise ELandrixXmlXsltError (an ELandrixXmlXPathError): the W3C
  code in XPathCode (XTSE.. for the stylesheet, XTDE.. for the run, or an
  XPath code such as FORG0001), the stylesheet module in ModuleUri and
  the position of the instruction in Line and Column. Code is xecXslt,
  xecXPath for an XPath expression that does not compile, and
  xecUnsupported for a construct outside the subset.

  Resources (imported modules, doc(), document(), unparsed-text()) come
  from a TLandrixXmlXsltResolver: by default files relative to the base
  URI, never the network. The default reads any file: URI a stylesheet
  names (also outside its folder); for a stylesheet that is not trusted,
  override Resolve. }

unit LandrixXmlXslt;

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
  LandrixXmlXPathEval;

type
  ELandrixXmlXsltError = class(ELandrixXmlXPathError)
  private
    FModuleUri: TLandrixXmlUtf8;
  public
    { ACode xecXslt, xecXPath or xecUnsupported; ALine 0 if unknown }
    constructor CreateXslt(ACode: TLandrixXmlErrorCode; const AXPathCode, Msg: string;
      const AModuleUri: TLandrixXmlUtf8; ALine, AColumn: Integer);
    property ModuleUri: TLandrixXmlUtf8 read FModuleUri;
  end;

  TLandrixXmlXsltResourceKind = (xrkStylesheet, xrkDocument, xrkText);

  { Where the resources of a stylesheet come from. Resolve gets the base
    URI of the referring module or node and the reference as written; it
    returns the absolute URI (the identity of the resource: one load per
    URI and run) and a stream the caller frees, or False if there is no
    such resource. The default resolves Href against BaseUri, then looks
    the URI up in the catalog (AddFile, AddUtf8), then reads a file: URI
    from disk; other schemes give False. Not owned by the stylesheet or
    the transformer; read-only while they use it. }
  TLandrixXmlXsltResolver = class
  private
    FUris: TLandrixXmlUtf8Array;
    FFiles: TStringList;
    FTexts: TLandrixXmlUtf8Array;
    FCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddFile(const Uri: TLandrixXmlUtf8; const FileName: string);
    procedure AddUtf8(const Uri, Text: TLandrixXmlUtf8);
    function Resolve(Kind: TLandrixXmlXsltResourceKind; const BaseUri, Href: TLandrixXmlUtf8;
      out Uri: TLandrixXmlUtf8; out Content: TStream): Boolean; virtual;
  end;

  { A message of xsl:message. }
  TLandrixXmlXsltMessage = class
  private
    FTextUtf8: TLandrixXmlUtf8;
    FTerminate: Boolean;
    FModuleUri: TLandrixXmlUtf8;
    FLine: Integer;
    FColumn: Integer;
  public
    constructor Create(const AText: TLandrixXmlUtf8; ATerminate: Boolean; const AModuleUri: TLandrixXmlUtf8;
      ALine, AColumn: Integer);
    { the string value of the message's content }
    property TextUtf8: TLandrixXmlUtf8 read FTextUtf8;
    property Terminate: Boolean read FTerminate;
    property ModuleUri: TLandrixXmlUtf8 read FModuleUri;
    property Line: Integer read FLine;
    property Column: Integer read FColumn;
  end;

  TLandrixXmlXsltStylesheet = class
  private
    FCompiled: TObject;
    procedure CheckUnloaded;
    function GetParameterCount: Integer;
    function GetParameterName(Index: Integer): TLandrixXmlUtf8;
    function GetParameterRequired(Index: Integer): Boolean;
  public
    destructor Destroy; override;
    { A stylesheet is loaded once (a second load raises xecInvalidOperation).
      The resolver is used while loading only; nil: the default. }
    procedure LoadFromFile(const FileName: string; Resolver: TLandrixXmlXsltResolver = nil);
    { the stream is read from its position, not freed }
    procedure LoadFromStream(Stream: TStream; const BaseUri: TLandrixXmlUtf8;
      Resolver: TLandrixXmlXsltResolver = nil);
    procedure LoadFromUtf8(const S, BaseUri: TLandrixXmlUtf8; Resolver: TLandrixXmlXsltResolver = nil);
    { the global parameters (after import precedence), Clark names }
    property ParameterCount: Integer read GetParameterCount;
    property ParameterNames[Index: Integer]: TLandrixXmlUtf8 read GetParameterName;
    property ParameterRequired[Index: Integer]: Boolean read GetParameterRequired;
    { internal: the compiled form (LandrixXmlXsltCompiler) }
    property Compiled: TObject read FCompiled;
  end;

  TLandrixXmlXsltTransformer = class
  private
    FStylesheet: TLandrixXmlXsltStylesheet;
    FParamNames: TLandrixXmlUtf8Array;
    { 0 a string (xs:untypedAtomic), 1 a tree, 2 an XPath expression }
    FParamKinds: array of Integer;
    FParamValues: TLandrixXmlUtf8Array;
    FParamTrees: array of TLandrixXmlXPathTree;
    FParamCount: Integer;
    FOutputNames: TLandrixXmlUtf8Array;
    FOutputValues: TLandrixXmlUtf8Array;
    FInitialMode: TLandrixXmlUtf8;
    FInitialTemplate: TLandrixXmlUtf8;
    FResolver: TLandrixXmlXsltResolver;
    FImplicitTimeZone: Integer;
    FClock: TLandrixXmlXsdDateTime;
    FHasClock: Boolean;
    FMaxDepth: Integer;
    FMaxTemplateDepth: Integer;
    FMessages: TObjectList;
    procedure SetParam(const Name: TLandrixXmlUtf8; Kind: Integer; const Value: TLandrixXmlUtf8;
      Tree: TLandrixXmlXPathTree);
    procedure SetImplicitTimeZone(Value: Integer);
    function GetMessageCount: Integer;
    function GetMessage(Index: Integer): TLandrixXmlXsltMessage;
    procedure Run(Source, Target: TLandrixXmlXPathTree; out Output: TObject);
  public
    { the stylesheet is not owned and must stay loaded }
    constructor Create(Stylesheet: TLandrixXmlXsltStylesheet);
    destructor Destroy; override;
    { a string parameter: an xs:untypedAtomic value (converted to the
      declared type as Saxon's command line does) }
    procedure SetParameter(const Name, Value: TLandrixXmlUtf8);
    { a document: the tree's document node; the tree is not owned }
    procedure SetParameterTree(const Name: TLandrixXmlUtf8; Tree: TLandrixXmlXPathTree);
    { the value of an XPath expression (Saxon profile, no focus, the
      namespaces xml, xs and fn) evaluated at the start of each run }
    procedure SetParameterXPath(const Name, Expression: TLandrixXmlUtf8);
    procedure ClearParameters;
    { overrides of xsl:output (indent, method, omit-xml-declaration, ...);
      raises for what xsl:output does not accept (xecUnsupported, and
      xecInvalidArgument for a name XSLT 2.0 does not define) }
    procedure SetOutputProperty(const Name, Value: TLandrixXmlUtf8);
    procedure ClearOutputProperties;
    { Runs the stylesheet on Source (its document node is the initial
      context; nil only with an InitialTemplate) and writes the principal
      result to Output at its position (UTF-8; another encoding raises
      xecUnsupported). }
    procedure Transform(Source: TLandrixXmlXPathTree; Output: TStream);
    { the result serialized as UTF-8, whatever xsl:output says }
    function TransformToUtf8(Source: TLandrixXmlXPathTree): TLandrixXmlUtf8;
    { the principal result as a tree (with a document node); xsl:output
      does not matter }
    procedure TransformToTree(Source, Target: TLandrixXmlXPathTree);
    { Clark names; '' = the default mode and applying templates to the
      source }
    property InitialMode: TLandrixXmlUtf8 read FInitialMode write FInitialMode;
    property InitialTemplate: TLandrixXmlUtf8 read FInitialTemplate write FInitialTemplate;
    { doc(), document() and unparsed-text(); nil: the default }
    property Resolver: TLandrixXmlXsltResolver read FResolver write FResolver;
    { as TLandrixXmlXPathEvaluator }
    property ImplicitTimeZone: Integer read FImplicitTimeZone write SetImplicitTimeZone;
    procedure SetCurrentDateTime(const Value: TLandrixXmlXsdDateTime);
    procedure ClearCurrentDateTime;
    { nesting of stylesheet and XPath user functions (default 500) and of
      template calls (default 1000); deeper raises xecLimit }
    property MaxDepth: Integer read FMaxDepth write FMaxDepth;
    property MaxTemplateDepth: Integer read FMaxTemplateDepth write FMaxTemplateDepth;
    { the messages of the last run (also after XTMM9000) }
    property MessageCount: Integer read GetMessageCount;
    property Messages[Index: Integer]: TLandrixXmlXsltMessage read GetMessage;
  end;

{ internal: a name as written (Clark notation, with an empty or no URI
  part, or an NCName) in the form
  the XSLT units keep (local for no namespace) }
function LandrixXmlXsltClark(const Name: TLandrixXmlUtf8): TLandrixXmlUtf8;
{ internal: the file name of a file: URI, '' for another URI }
function LandrixXmlXsltUriToFileName(const Uri: TLandrixXmlUtf8): string;

implementation

uses
  LandrixXmlReader,
  LandrixXmlXsltCompiler,
  LandrixXmlXsltRuntime,
  LandrixXmlXsltOutput;

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

{ --- ELandrixXmlXsltError ------------------------------------------------ }

constructor ELandrixXmlXsltError.CreateXslt(ACode: TLandrixXmlErrorCode; const AXPathCode, Msg: string;
  const AModuleUri: TLandrixXmlUtf8; ALine, AColumn: Integer);
var
  Where: string;
begin
  Where := '';
  if AModuleUri <> '' then
    Where := ' in ' + LandrixXmlUtf8ToString(AModuleUri);
  inherited CreateXPathAt(ACode, AXPathCode, Msg + Where, ALine, AColumn);
  FModuleUri := AModuleUri;
end;

{ --- names and URIs ------------------------------------------------------- }

function LandrixXmlXsltClark(const Name: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := Name;
  if (Name = '') or (Name[1] <> '{') then
    Exit;
  I := Pos8('}', Name);
  if I = 2 then
    Result := Copy(Name, 3, Length(Name) - 2);
end;

function HexValue(C: AnsiChar): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function LandrixXmlXsltUriToFileName(const Uri: TLandrixXmlUtf8): string;
var
  Path, Decoded: TLandrixXmlUtf8;
  I, N: Integer;
begin
  Result := '';
  if LowerCase(Copy(LandrixXmlUtf8ToString(Uri), 1, 5)) <> 'file:' then
    Exit;
  Path := Copy(Uri, 6, Length(Uri) - 5);
  { file:///D:/x, file://localhost/x and file:/D:/x }
  if Copy(Path, 1, 2) = '//' then
  begin
    Delete(Path, 1, 2);
    I := Pos8('/', Path);
    if I = 0 then
      Exit;
    Delete(Path, 1, I - 1);
  end;
  I := Pos8('#', Path);
  if I > 0 then
    Path := Copy(Path, 1, I - 1);
  I := Pos8('?', Path);
  if I > 0 then
    Path := Copy(Path, 1, I - 1);
  Decoded := '';
  SetLength(Decoded, Length(Path));
  N := 0;
  I := 1;
  while I <= Length(Path) do
  begin
    Inc(N);
    if (Path[I] = '%') and (I + 2 <= Length(Path)) and (HexValue(Path[I + 1]) >= 0) and
      (HexValue(Path[I + 2]) >= 0) then
    begin
      Decoded[N] := AnsiChar(HexValue(Path[I + 1]) * 16 + HexValue(Path[I + 2]));
      Inc(I, 3);
    end
    else
    begin
      Decoded[N] := Path[I];
      Inc(I);
    end;
  end;
  SetLength(Decoded, N);
  {$IFDEF MSWINDOWS}
  { /D:/x is D:/x }
  if (Length(Decoded) >= 3) and (Decoded[1] = '/') and (Decoded[3] = ':') then
    Delete(Decoded, 1, 1);
  for I := 1 to Length(Decoded) do
    if Decoded[I] = '/' then
      Decoded[I] := '\';
  {$ENDIF}
  Result := LandrixXmlUtf8ToString(Decoded);
end;

{ --- TLandrixXmlXsltResolver ---------------------------------------------- }

constructor TLandrixXmlXsltResolver.Create;
begin
  inherited Create;
  FFiles := TXsltStringList.Create;
end;

destructor TLandrixXmlXsltResolver.Destroy;
begin
  FFiles.Free;
  inherited Destroy;
end;

procedure TLandrixXmlXsltResolver.AddFile(const Uri: TLandrixXmlUtf8; const FileName: string);
begin
  if FCount = Length(FUris) then
  begin
    SetLength(FUris, 2 * FCount + 4);
    SetLength(FTexts, 2 * FCount + 4);
  end;
  FUris[FCount] := Uri;
  FTexts[FCount] := '';
  FFiles.Add(FileName);
  Inc(FCount);
end;

procedure TLandrixXmlXsltResolver.AddUtf8(const Uri, Text: TLandrixXmlUtf8);
begin
  if FCount = Length(FUris) then
  begin
    SetLength(FUris, 2 * FCount + 4);
    SetLength(FTexts, 2 * FCount + 4);
  end;
  FUris[FCount] := Uri;
  FTexts[FCount] := Text;
  { no file: the text }
  FFiles.Add('');
  Inc(FCount);
end;

function TLandrixXmlXsltResolver.Resolve(Kind: TLandrixXmlXsltResourceKind; const BaseUri, Href: TLandrixXmlUtf8;
  out Uri: TLandrixXmlUtf8; out Content: TStream): Boolean;
var
  I: Integer;
  FileName: string;
  M: TMemoryStream;
begin
  Result := False;
  Content := nil;
  Uri := '';
  { an empty reference to a stylesheet module is the module itself }
  if (Kind = xrkStylesheet) and (Href = '') then
    Exit;
  if BaseUri <> '' then
    Uri := LandrixXmlXPathResolveUri(Href, BaseUri)
  else
    Uri := Href;
  for I := FCount - 1 downto 0 do
    if (FUris[I] = Uri) or (FUris[I] = Href) then
    begin
      if FFiles[I] = '' then
      begin
        M := TMemoryStream.Create;
        if FTexts[I] <> '' then
          M.WriteBuffer(PAnsiChar(FTexts[I])^, Length(FTexts[I]));
        M.Position := 0;
        Content := M;
      end
      else
        Content := TFileStream.Create(FFiles[I], fmOpenRead or fmShareDenyWrite);
      Result := True;
      Exit;
    end;
  FileName := LandrixXmlXsltUriToFileName(Uri);
  if (FileName = '') or not FileExists(FileName) then
    Exit;
  Content := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  Result := True;
end;

{ --- TLandrixXmlXsltMessage ------------------------------------------------ }

constructor TLandrixXmlXsltMessage.Create(const AText: TLandrixXmlUtf8; ATerminate: Boolean;
  const AModuleUri: TLandrixXmlUtf8; ALine, AColumn: Integer);
begin
  inherited Create;
  FTextUtf8 := AText;
  FTerminate := ATerminate;
  FModuleUri := AModuleUri;
  FLine := ALine;
  FColumn := AColumn;
end;

{ --- TLandrixXmlXsltStylesheet --------------------------------------------- }

destructor TLandrixXmlXsltStylesheet.Destroy;
begin
  FCompiled.Free;
  inherited Destroy;
end;

procedure TLandrixXmlXsltStylesheet.CheckUnloaded;
begin
  if FCompiled <> nil then
    raise ELandrixXmlError.CreateCode(xecInvalidOperation, 'XSLT: the stylesheet is already loaded');
end;

procedure TLandrixXmlXsltStylesheet.LoadFromFile(const FileName: string; Resolver: TLandrixXmlXsltResolver);
var
  Tree: TLandrixXmlXPathTree;
begin
  CheckUnloaded;
  Tree := TLandrixXmlXPathTree.Create;
  try
    Tree.LoadFromFile(FileName);
    FCompiled := XsltCompile(Tree, Tree.BaseUri, Resolver);
  finally
    Tree.Free;
  end;
end;

procedure TLandrixXmlXsltStylesheet.LoadFromStream(Stream: TStream; const BaseUri: TLandrixXmlUtf8;
  Resolver: TLandrixXmlXsltResolver);
var
  Tree: TLandrixXmlXPathTree;
  Reader: TLandrixXmlReader;
begin
  CheckUnloaded;
  Tree := TLandrixXmlXPathTree.Create;
  Reader := TLandrixXmlReader.Create;
  try
    Reader.LoadFromStream(Stream);
    Tree.LoadFromReader(Reader);
    Tree.BaseUri := BaseUri;
    FCompiled := XsltCompile(Tree, BaseUri, Resolver);
  finally
    Reader.Free;
    Tree.Free;
  end;
end;

procedure TLandrixXmlXsltStylesheet.LoadFromUtf8(const S, BaseUri: TLandrixXmlUtf8;
  Resolver: TLandrixXmlXsltResolver);
var
  Tree: TLandrixXmlXPathTree;
begin
  CheckUnloaded;
  Tree := TLandrixXmlXPathTree.Create;
  try
    Tree.LoadFromUtf8(S);
    Tree.BaseUri := BaseUri;
    FCompiled := XsltCompile(Tree, BaseUri, Resolver);
  finally
    Tree.Free;
  end;
end;

function TLandrixXmlXsltStylesheet.GetParameterCount: Integer;
begin
  Result := 0;
  if FCompiled <> nil then
    Result := XsltParameterCount(FCompiled);
end;

function TLandrixXmlXsltStylesheet.GetParameterName(Index: Integer): TLandrixXmlUtf8;
begin
  Result := XsltParameterName(FCompiled, Index);
end;

function TLandrixXmlXsltStylesheet.GetParameterRequired(Index: Integer): Boolean;
begin
  Result := XsltParameterRequired(FCompiled, Index);
end;

{ --- TLandrixXmlXsltTransformer -------------------------------------------- }

constructor TLandrixXmlXsltTransformer.Create(Stylesheet: TLandrixXmlXsltStylesheet);
begin
  inherited Create;
  if (Stylesheet = nil) or (Stylesheet.Compiled = nil) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'XSLT: the transformer needs a loaded stylesheet');
  FStylesheet := Stylesheet;
  FMessages := TObjectList.Create;
  FMaxDepth := 500;
  FMaxTemplateDepth := 1000;
end;

destructor TLandrixXmlXsltTransformer.Destroy;
begin
  FMessages.Free;
  inherited Destroy;
end;

procedure TLandrixXmlXsltTransformer.SetParam(const Name: TLandrixXmlUtf8; Kind: Integer;
  const Value: TLandrixXmlUtf8; Tree: TLandrixXmlXPathTree);
var
  I: Integer;
  N: TLandrixXmlUtf8;
begin
  N := LandrixXmlXsltClark(Name);
  if N = '' then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'XSLT: a parameter needs a name');
  I := 0;
  while (I < FParamCount) and (FParamNames[I] <> N) do
    Inc(I);
  if I = FParamCount then
  begin
    if FParamCount = Length(FParamNames) then
    begin
      SetLength(FParamNames, 2 * FParamCount + 4);
      SetLength(FParamKinds, 2 * FParamCount + 4);
      SetLength(FParamValues, 2 * FParamCount + 4);
      SetLength(FParamTrees, 2 * FParamCount + 4);
    end;
    Inc(FParamCount);
  end;
  FParamNames[I] := N;
  FParamKinds[I] := Kind;
  FParamValues[I] := Value;
  FParamTrees[I] := Tree;
end;

procedure TLandrixXmlXsltTransformer.SetParameter(const Name, Value: TLandrixXmlUtf8);
begin
  SetParam(Name, 0, Value, nil);
end;

procedure TLandrixXmlXsltTransformer.SetParameterTree(const Name: TLandrixXmlUtf8; Tree: TLandrixXmlXPathTree);
begin
  if (Tree = nil) or (Tree.Kind[0] <> xnkDocument) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'XSLT: a parameter tree needs a document node');
  SetParam(Name, 1, '', Tree);
end;

procedure TLandrixXmlXsltTransformer.SetParameterXPath(const Name, Expression: TLandrixXmlUtf8);
begin
  SetParam(Name, 2, Expression, nil);
end;

procedure TLandrixXmlXsltTransformer.ClearParameters;
begin
  FParamNames := nil;
  FParamKinds := nil;
  FParamValues := nil;
  FParamTrees := nil;
  FParamCount := 0;
end;

procedure TLandrixXmlXsltTransformer.SetOutputProperty(const Name, Value: TLandrixXmlUtf8);
var
  I: Integer;
begin
  { the checks of xsl:output }
  case XsltOutputPropertyStatus(Name, Value) of
    xosUnsupported:
      raise ELandrixXmlXsltError.CreateXslt(xecUnsupported, 'FOER0000', 'the output property ' +
        LandrixXmlUtf8ToString(Name) + '="' + LandrixXmlUtf8ToString(Value) + '" is not supported', '', 0, 0);
    xosUnknown:
      raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'SetOutputProperty: no output property ' +
        LandrixXmlUtf8ToString(Name));
  else
    { supported }
  end;
  for I := 0 to Integer(Length(FOutputNames)) - 1 do
    if FOutputNames[I] = Name then
    begin
      FOutputValues[I] := Value;
      Exit;
    end;
  I := Integer(Length(FOutputNames));
  SetLength(FOutputNames, I + 1);
  SetLength(FOutputValues, I + 1);
  FOutputNames[I] := Name;
  FOutputValues[I] := Value;
end;

procedure TLandrixXmlXsltTransformer.ClearOutputProperties;
begin
  FOutputNames := nil;
  FOutputValues := nil;
end;

procedure TLandrixXmlXsltTransformer.SetImplicitTimeZone(Value: Integer);
begin
  if (Value < -840) or (Value > 840) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'ImplicitTimeZone must be between -840 and 840 minutes');
  FImplicitTimeZone := Value;
end;

procedure TLandrixXmlXsltTransformer.SetCurrentDateTime(const Value: TLandrixXmlXsdDateTime);
begin
  FClock := Value;
  FHasClock := True;
end;

procedure TLandrixXmlXsltTransformer.ClearCurrentDateTime;
begin
  FHasClock := False;
end;

function TLandrixXmlXsltTransformer.GetMessageCount: Integer;
begin
  Result := Integer(FMessages.Count);
end;

function TLandrixXmlXsltTransformer.GetMessage(Index: Integer): TLandrixXmlXsltMessage;
begin
  Result := TLandrixXmlXsltMessage(FMessages[Index]);
end;

{ One run into Target; Output: the output properties in effect (a
  TXsltOutputProperties the caller frees). }
procedure TLandrixXmlXsltTransformer.Run(Source, Target: TLandrixXmlXPathTree; out Output: TObject);
var
  Settings: TXsltRunSettings;
  I: Integer;
  Props: TXsltOutputProperties;
begin
  Output := nil;
  FMessages.Clear;
  Settings := TXsltRunSettings.Create;
  try
    for I := 0 to FParamCount - 1 do
      Settings.AddParameter(FParamNames[I], FParamKinds[I], FParamValues[I], FParamTrees[I]);
    Settings.InitialMode := LandrixXmlXsltClark(FInitialMode);
    Settings.InitialTemplate := LandrixXmlXsltClark(FInitialTemplate);
    Settings.Resolver := FResolver;
    Settings.ImplicitTimeZone := FImplicitTimeZone;
    Settings.HasClock := FHasClock;
    Settings.Clock := FClock;
    Settings.MaxDepth := FMaxDepth;
    Settings.MaxTemplateDepth := FMaxTemplateDepth;
    Settings.Messages := FMessages;
    XsltRun(FStylesheet.Compiled, Settings, Source, Target);
  finally
    Settings.Free;
  end;
  Props := XsltOutputProperties(FStylesheet.Compiled);
  for I := 0 to Integer(Length(FOutputNames)) - 1 do
    Props.SetValue(FOutputNames[I], FOutputValues[I]);
  Output := Props;
end;

procedure TLandrixXmlXsltTransformer.TransformToTree(Source, Target: TLandrixXmlXPathTree);
var
  Props: TObject;
begin
  if Target = nil then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'XSLT: TransformToTree needs a target tree');
  Run(Source, Target, Props);
  Props.Free;
end;

procedure TLandrixXmlXsltTransformer.Transform(Source: TLandrixXmlXPathTree; Output: TStream);
var
  Target: TLandrixXmlXPathTree;
  Props: TObject;
begin
  Target := TLandrixXmlXPathTree.Create;
  Props := nil;
  try
    Run(Source, Target, Props);
    XsltSerialize(Target, TXsltOutputProperties(Props), Output, False);
  finally
    Props.Free;
    Target.Free;
  end;
end;

function TLandrixXmlXsltTransformer.TransformToUtf8(Source: TLandrixXmlXPathTree): TLandrixXmlUtf8;
var
  Target: TLandrixXmlXPathTree;
  Props: TObject;
  M: TMemoryStream;
begin
  Result := '';
  Target := TLandrixXmlXPathTree.Create;
  Props := nil;
  M := TMemoryStream.Create;
  try
    Run(Source, Target, Props);
    XsltSerialize(Target, TXsltOutputProperties(Props), M, True);
    SetLength(Result, Integer(M.Size));
    M.Position := 0;
    if M.Size > 0 then
      M.ReadBuffer(PAnsiChar(Result)^, Integer(M.Size));
  finally
    M.Free;
    Props.Free;
    Target.Free;
  end;
end;

end.
