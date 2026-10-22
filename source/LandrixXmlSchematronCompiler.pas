{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Compiles an ISO Schematron file (queryBinding xslt2 or xslt3, as the
  EN16931, XRechnung and Peppol rules are written) into the rule file
  LandrixXmlSchematron loads (namespace urn:landrix:schematron-rules,
  format 1); tools/sch-compile.py does the same and is the reference.

  Handled: sch:include (replaced by the included element where it stands,
  relative to the including file; cycles are rejected), sch:ns, sch:let in
  the schema and in patterns (global) and in rules (per rule), sch:pattern,
  sch:rule, sch:assert and sch:report (id, flag, role, test, the message
  with sch:name and sch:value-of; sch:emph, sch:dir and sch:span add their
  content), sch:phase (a default phase must activate every pattern with a
  rule; without one all patterns run, as in SchXslt), and the XSLT
  functions the XRechnung and Peppol rules use: xsl:function with
  xsl:param, xsl:variable (select, text content, or one xsl:sequence child
  with "as") and one result, xsl:sequence or xsl:choose around it.
  Variables inside a choose branch become function variables (they are
  evaluated lazily, so the result is the same); their names must be
  unique in the function, and every function expression is compiled with
  only the variables visible where it stands, so that a lifted variable
  is not seen outside its branch. Elements of other namespaces (documentation)
  are ignored.

  Rejected with file and line, never dropped: abstract patterns and rules,
  sch:extends, sch:diagnostics, sch:properties, the attributes
  diagnostics, properties and subject of checks, documents of patterns,
  "as" of lets, other phases, other XSLT elements, elements without a
  namespace. The expressions are copied with white space outside string
  literals collapsed; the XPath parser checks them when the rules are
  loaded. AddOverride replaces the test of one check (for a rule set
  whose source and the XSLT a validator runs differ); the rule file then
  keeps the source's test as "original". }

unit LandrixXmlSchematronCompiler;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  Contnrs,
  LandrixXmlBase,
  LandrixXmlDom;

type
  TLandrixXmlSchematronCompiler = class
  private
    FUrl: TLandrixXmlUtf8;
    FOverrideIds: TLandrixXmlUtf8Array;
    FOverrideTests: TLandrixXmlUtf8Array;
    FOverrideOriginals: TLandrixXmlUtf8Array;
    { the state of one compilation }
    FDocuments: TObjectList;
    FDocumentFiles: TStringList;
    FIncluding: TStringList;
    FNsPrefixes: TLandrixXmlUtf8Array;
    FNsUris: TLandrixXmlUtf8Array;
    FGlobals: TObjectList;
    FFunctions: TObjectList;
    FPatterns: TObjectList;
    { the function expressions with the names visible where they stand }
    FScopeChecks: TObjectList;
    procedure Reset;
    function Where(Node: TLandrixXmlNode): string;
    procedure Fail(Node: TLandrixXmlNode; const Msg: string);
    procedure Unsupported(Node: TLandrixXmlNode; const Msg: string);
    function LoadDocument(const FileName: string): TLandrixXmlDocument;
    function Include(Node: TLandrixXmlNode): TLandrixXmlNode;
    procedure Walk(Node: TLandrixXmlNode);
    procedure AddNamespace(Node: TLandrixXmlNode);
    procedure AddGlobal(Node: TLandrixXmlNode);
    procedure AddPattern(Node: TLandrixXmlNode);
    function CompileRule(Node: TLandrixXmlNode): TObject;
    function CompileCheck(Node: TLandrixXmlNode): TObject;
    procedure AddFunction(Node: TLandrixXmlNode);
    procedure CheckPhases(Main: TLandrixXmlNode);
    procedure CheckScopes;
    procedure ApplyOverrides;
    function Write(Main: TLandrixXmlNode; const Sha256, FileName: string): TLandrixXmlDocument;
  public
    constructor Create;
    destructor Destroy; override;
    { Replaces the test of the check with this id (exactly one must have
      it) by Test; ExpectedOriginal must be the check's test as written
      (white space outside strings does not matter), so that a changed
      source does not keep a stale replacement. }
    procedure AddOverride(const Id, Test, ExpectedOriginal: TLandrixXmlUtf8);
    procedure ClearOverrides;
    { The rule file of the Schematron file FileName; the caller frees it.
      Raises ELandrixXmlError: xecSchema for invalid Schematron (and the
      reader's errors for malformed XML), xecUnsupported for constructs
      outside the supported subset; the message names file and line. }
    function CompileFile(const FileName: string): TLandrixXmlDocument;
    { written to the rule file as url (where the rule set comes from) }
    property Url: TLandrixXmlUtf8 read FUrl write FUrl;
  end;

{ White space runs (space, tab, CR, LF) outside XPath string literals
  and comments become one space; the result is trimmed. }
function LandrixXmlSchematronCollapse(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;

implementation

uses
  LandrixXmlXPath,
  LandrixXmlSha256;

const
  SchNs = 'http://purl.oclc.org/dsdl/schematron';
  XslNs = 'http://www.w3.org/1999/XSL/Transform';
  RulesNs = 'urn:landrix:schematron-rules';

type
  TGlobal = class
  public
    Name, Value, Line: TLandrixXmlUtf8;
  end;

  TPart = class
  public
    Kind: TLandrixXmlUtf8; { text, value-of, name }
    Value: TLandrixXmlUtf8;
  end;

  TCheck = class
  public
    Kind, Id, Flag, Role, Test, Line, Original: TLandrixXmlUtf8;
    HasOriginal: Boolean;
    Parts: TObjectList;
    constructor Create;
    destructor Destroy; override;
  end;

  TRule = class
  public
    Context, Id, Line: TLandrixXmlUtf8;
    LetNames, LetValues: TLandrixXmlUtf8Array;
    Checks: TObjectList;
    constructor Create;
    destructor Destroy; override;
  end;

  TPattern = class
  public
    Id: TLandrixXmlUtf8;
    Rules: TObjectList;
    constructor Create;
    destructor Destroy; override;
  end;

  TFunctionVariable = class
  public
    Name, AsType, Value: TLandrixXmlUtf8;
  end;

  TFunction = class
  public
    Name, AsType, Line, Result: TLandrixXmlUtf8;
    ParamNames, ParamTypes: TLandrixXmlUtf8Array;
    Variables: TObjectList;
    { every parameter and variable name, to find duplicates }
    Names: TLandrixXmlUtf8Array;
    { the names visible where an expression stands (the first
      VisibleCount): the parameters, the variables declared before it at
      its level and in the branches around it; variables lifted out of a
      branch must not be seen outside it }
    Visible: TLandrixXmlUtf8Array;
    VisibleCount: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TScopeCheck = class
  public
    Node: TLandrixXmlNode;
    Expression: TLandrixXmlUtf8;
    FunctionName: TLandrixXmlUtf8;
    Names: TLandrixXmlUtf8Array;
  end;

constructor TCheck.Create;
begin
  inherited Create;
  Parts := TObjectList.Create(True);
end;

destructor TCheck.Destroy;
begin
  Parts.Free;
  inherited Destroy;
end;

constructor TRule.Create;
begin
  inherited Create;
  Checks := TObjectList.Create(True);
end;

destructor TRule.Destroy;
begin
  Checks.Free;
  inherited Destroy;
end;

constructor TPattern.Create;
begin
  inherited Create;
  Rules := TObjectList.Create(True);
end;

destructor TPattern.Destroy;
begin
  Rules.Free;
  inherited Destroy;
end;

constructor TFunction.Create;
begin
  inherited Create;
  Variables := TObjectList.Create(True);
end;

destructor TFunction.Destroy;
begin
  Variables.Free;
  inherited Destroy;
end;

{ --- helpers ------------------------------------------------------------- }

function U(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

function S8(const S: TLandrixXmlUtf8): string;
begin
  Result := LandrixXmlUtf8ToString(S);
end;

function IsSpace(C: AnsiChar): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13);
end;

function LandrixXmlSchematronCollapse(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I, J, N, Count, Depth: Integer;
  Quote: AnsiChar;
begin
  Result := '';
  SetLength(Result, Length(S));
  N := 0;
  I := 1;
  Count := Integer(Length(S));
  while I <= Count do
  begin
    if (S[I] = '(') and (I < Count) and (S[I + 1] = ':') then
    begin
      { a comment, nested ones too, as it is (quotes inside are no strings) }
      Depth := 0;
      J := I;
      while J <= Count do
      begin
        if (S[J] = '(') and (J < Count) and (S[J + 1] = ':') then
        begin
          Inc(Depth);
          Inc(J, 2);
        end
        else if (S[J] = ':') and (J < Count) and (S[J + 1] = ')') then
        begin
          Dec(Depth);
          Inc(J, 2);
          if Depth = 0 then
            Break;
        end
        else
          Inc(J);
      end;
      if J > Count + 1 then
        J := Count + 1;
      while I < J do
      begin
        Inc(N);
        Result[N] := S[I];
        Inc(I);
      end;
    end
    else if (S[I] = '''') or (S[I] = '"') then
    begin
      { a literal up to its closing quote; a doubled quote stays inside }
      Quote := AnsiChar(S[I]);
      J := I + 1;
      while J <= Count do
      begin
        if AnsiChar(S[J]) = Quote then
        begin
          if (J < Count) and (AnsiChar(S[J + 1]) = Quote) then
          begin
            Inc(J, 2);
            Continue;
          end;
          Break;
        end;
        Inc(J);
      end;
      if J > Count then
        J := Count;
      while I <= J do
      begin
        Inc(N);
        Result[N] := S[I];
        Inc(I);
      end;
    end
    else if IsSpace(AnsiChar(S[I])) then
    begin
      while (I <= Count) and IsSpace(AnsiChar(S[I])) do
        Inc(I);
      Inc(N);
      Result[N] := ' ';
    end
    else
    begin
      Inc(N);
      Result[N] := S[I];
      Inc(I);
    end;
  end;
  SetLength(Result, N);
  { trim }
  I := 1;
  while (I <= N) and IsSpace(AnsiChar(Result[I])) do
    Inc(I);
  J := N;
  while (J >= I) and IsSpace(AnsiChar(Result[J])) do
    Dec(J);
  Result := Copy(Result, I, J - I + 1);
end;

{ the whole text below Node (text and CDATA, in document order) }
function TextBelow(Node: TLandrixXmlNode): TLandrixXmlUtf8;
var
  C: TLandrixXmlNode;
begin
  Result := '';
  C := Node.FirstChild;
  while C <> nil do
  begin
    case C.NodeType of
      LandrixXmlDom.xntText, LandrixXmlDom.xntCData:
        Result := Result + C.ValueUtf8;
      LandrixXmlDom.xntElement:
        Result := Result + TextBelow(C);
    else
      { comments and processing instructions are no text }
    end;
    C := C.NextSibling;
  end;
end;

{ only white space (space, tab, CR, LF) or empty }
function IsBlank(const S: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 1 to Length(S) do
    if not IsSpace(AnsiChar(S[I])) then
    begin
      Result := False;
      Exit;
    end;
end;

function IsSch(Node: TLandrixXmlNode; const LocalName: string): Boolean;
begin
  Result := (Node <> nil) and (Node.NodeType = LandrixXmlDom.xntElement) and (Node.NamespaceUriUtf8 = SchNs) and
    (Node.LocalNameUtf8 = U(LocalName));
end;

function IsXsl(Node: TLandrixXmlNode; const LocalName: string): Boolean;
begin
  Result := (Node <> nil) and (Node.NodeType = LandrixXmlDom.xntElement) and (Node.NamespaceUriUtf8 = XslNs) and
    (Node.LocalNameUtf8 = U(LocalName));
end;

function Attr(Node: TLandrixXmlNode; const Name: string): TLandrixXmlUtf8;
begin
  Result := Node.AttributeValueUtf8(U(''), U(Name));
end;

function HasAttr(Node: TLandrixXmlNode; const Name: string): Boolean;
begin
  Result := Node.HasAttribute(U(''), U(Name));
end;

function StringLiteral(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := '''';
  for I := 1 to Length(S) do
    if S[I] = '''' then
      Result := Result + ''''''
    else
      Result := Result + Copy(S, I, 1);
  Result := Result + '''';
end;

function IndexOfUtf8(const List: TLandrixXmlUtf8Array; const S: TLandrixXmlUtf8): Integer;
var
  I: Integer;
begin
  for I := 0 to Integer(Length(List)) - 1 do
    if List[I] = S then
    begin
      Result := I;
      Exit;
    end;
  Result := -1;
end;

procedure AddUtf8(var List: TLandrixXmlUtf8Array; const S: TLandrixXmlUtf8);
var
  N: Integer;
begin
  N := Integer(Length(List));
  SetLength(List, N + 1);
  List[N] := S;
end;

function FileBytes(const FileName: string): TLandrixXmlUtf8;
var
  Stream: TFileStream;
begin
  Result := '';
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, Integer(Stream.Size));
    if Length(Result) > 0 then
      Stream.ReadBuffer(Result[1], Length(Result));
  finally
    Stream.Free;
  end;
end;

{ --- TLandrixXmlSchematronCompiler ------------------------------------------ }

constructor TLandrixXmlSchematronCompiler.Create;
begin
  inherited Create;
  FDocuments := TObjectList.Create(True);
  FDocumentFiles := TStringList.Create;
  FIncluding := TStringList.Create;
  FGlobals := TObjectList.Create(True);
  FFunctions := TObjectList.Create(True);
  FPatterns := TObjectList.Create(True);
  FScopeChecks := TObjectList.Create(True);
end;

destructor TLandrixXmlSchematronCompiler.Destroy;
begin
  Reset;
  FScopeChecks.Free;
  FPatterns.Free;
  FFunctions.Free;
  FGlobals.Free;
  FIncluding.Free;
  FDocumentFiles.Free;
  FDocuments.Free;
  inherited Destroy;
end;

procedure TLandrixXmlSchematronCompiler.AddOverride(const Id, Test, ExpectedOriginal: TLandrixXmlUtf8);
var
  I: Integer;
begin
  if (Id = '') or (LandrixXmlSchematronCollapse(Test) = '') then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'Schematron override: id and test are needed');
  for I := 0 to Integer(Length(FOverrideIds)) - 1 do
    if FOverrideIds[I] = Id then
      raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'Schematron override: ' + S8(Id) + ' is given twice');
  AddUtf8(FOverrideIds, Id);
  AddUtf8(FOverrideTests, Test);
  AddUtf8(FOverrideOriginals, ExpectedOriginal);
end;

procedure TLandrixXmlSchematronCompiler.ClearOverrides;
begin
  FOverrideIds := nil;
  FOverrideTests := nil;
  FOverrideOriginals := nil;
end;

procedure TLandrixXmlSchematronCompiler.Reset;
begin
  FScopeChecks.Clear;
  FPatterns.Clear;
  FFunctions.Clear;
  FGlobals.Clear;
  FNsPrefixes := nil;
  FNsUris := nil;
  FIncluding.Clear;
  FDocumentFiles.Clear;
  FDocuments.Clear;
end;

function TLandrixXmlSchematronCompiler.Where(Node: TLandrixXmlNode): string;
var
  I: Integer;
begin
  Result := '?';
  for I := 0 to Integer(FDocuments.Count) - 1 do
    if Node.Document = FDocuments[I] then
      Result := ExtractFileName(FDocumentFiles[I]);
  Result := Result + ':' + IntToStr(Node.Line);
end;

procedure TLandrixXmlSchematronCompiler.Fail(Node: TLandrixXmlNode; const Msg: string);
begin
  if Node <> nil then
    raise ELandrixXmlError.CreateCode(xecSchema, 'Schematron: ' + Where(Node) + ': ' + Msg);
  raise ELandrixXmlError.CreateCode(xecSchema, 'Schematron: ' + Msg);
end;

procedure TLandrixXmlSchematronCompiler.Unsupported(Node: TLandrixXmlNode; const Msg: string);
begin
  raise ELandrixXmlError.CreateCode(xecUnsupported, 'Schematron: ' + Where(Node) + ': ' + Msg);
end;

function TLandrixXmlSchematronCompiler.LoadDocument(const FileName: string): TLandrixXmlDocument;
begin
  Result := TLandrixXmlDocument.Create;
  FDocuments.Add(Result);
  FDocumentFiles.Add(FileName);
  Result.KeepComments := False;
  Result.KeepProcessingInstructions := False;
  Result.WhitespaceMode := xwmPreserve;
  Result.LoadFromFile(FileName);
end;

{ The root element of the file an sch:include names. }
function TLandrixXmlSchematronCompiler.Include(Node: TLandrixXmlNode): TLandrixXmlNode;
var
  Href, Base, Path: string;
  I: Integer;
begin
  Href := S8(Attr(Node, 'href'));
  if (Href = '') or (Pos('#', Href) > 0) then
    Unsupported(Node, 'sch:include needs a plain href');
  Base := '';
  for I := 0 to Integer(FDocuments.Count) - 1 do
    if Node.Document = FDocuments[I] then
      Base := ExtractFilePath(FDocumentFiles[I]);
  Href := StringReplace(Href, '/', PathDelim, [rfReplaceAll]);
  { a rooted href (/x, \x, C:x) as it is, a relative one from the including file }
  if (Href[1] = PathDelim) or ((Length(Href) >= 2) and (Href[2] = ':')) then
    Path := ExpandFileName(Href)
  else
    Path := ExpandFileName(Base + Href);
  for I := 0 to Integer(FIncluding.Count) - 1 do
    if SameFileName(FIncluding[I], Path) then
      Fail(Node, 'sch:include of ' + Href + ' is circular');
  FIncluding.Add(Path);
  Result := LoadDocument(Path).Root;
end;

procedure TLandrixXmlSchematronCompiler.Walk(Node: TLandrixXmlNode);
var
  C, Inc: TLandrixXmlNode;
  L: string;
begin
  if Node.NamespaceUriUtf8 = SchNs then
  begin
    L := S8(Node.LocalNameUtf8);
    if L = 'schema' then
    begin
      C := Node.FirstChildElement;
      while C <> nil do
      begin
        Walk(C);
        C := C.NextSiblingElement;
      end;
    end
    else if L = 'include' then
    begin
      Inc := Include(Node);
      if IsSch(Inc, 'schema') then
        Unsupported(Node, 'sch:include of a whole schema is not supported');
      Walk(Inc);
      FIncluding.Delete(FIncluding.Count - 1);
    end
    else if (L = 'title') or (L = 'p') or (L = 'phase') or (L = 'active') then
      { documentation; phases are checked by CheckPhases }
    else if L = 'ns' then
      AddNamespace(Node)
    else if L = 'let' then
      AddGlobal(Node)
    else if L = 'pattern' then
      AddPattern(Node)
    else if (L = 'diagnostics') or (L = 'properties') or (L = 'extends') then
      Unsupported(Node, 'sch:' + L + ' is not supported')
    else
      Fail(Node, 'unexpected sch:' + L);
  end
  else if Node.NamespaceUriUtf8 = XslNs then
  begin
    if IsXsl(Node, 'function') then
      AddFunction(Node)
    else
      Unsupported(Node, 'xsl:' + S8(Node.LocalNameUtf8) + ' outside a function is not supported');
  end
  else if Node.NamespaceUriUtf8 = '' then
    Fail(Node, 'element ' + S8(Node.LocalNameUtf8) + ' without namespace');
  { elements of other namespaces are documentation }
end;

procedure TLandrixXmlSchematronCompiler.AddNamespace(Node: TLandrixXmlNode);
var
  Prefix, Uri: TLandrixXmlUtf8;
  I: Integer;
begin
  Prefix := Attr(Node, 'prefix');
  Uri := Attr(Node, 'uri');
  if (Prefix = '') or not HasAttr(Node, 'uri') then
    Fail(Node, 'sch:ns needs prefix and uri');
  for I := 0 to Integer(Length(FNsPrefixes)) - 1 do
    if FNsPrefixes[I] = Prefix then
    begin
      if FNsUris[I] <> Uri then
        Fail(Node, 'the prefix ' + S8(Prefix) + ' is bound to two namespaces');
      Exit;
    end;
  AddUtf8(FNsPrefixes, Prefix);
  AddUtf8(FNsUris, Uri);
end;

procedure TLandrixXmlSchematronCompiler.AddGlobal(Node: TLandrixXmlNode);
var
  G: TGlobal;
  Name: TLandrixXmlUtf8;
  I: Integer;
begin
  Name := Attr(Node, 'name');
  for I := 0 to Integer(FGlobals.Count) - 1 do
    if TGlobal(FGlobals[I]).Name = Name then
      Fail(Node, 'global variable $' + S8(Name) + ' is defined twice');
  if not HasAttr(Node, 'value') then
    Unsupported(Node, 'a let without value is not supported');
  if HasAttr(Node, 'as') then
    Unsupported(Node, 'a let with "as" is not supported');
  G := TGlobal.Create;
  FGlobals.Add(G);
  G.Name := Name;
  G.Value := LandrixXmlSchematronCollapse(Attr(Node, 'value'));
  G.Line := U(Where(Node));
end;

procedure TLandrixXmlSchematronCompiler.AddPattern(Node: TLandrixXmlNode);
var
  P: TPattern;

  procedure Member(C: TLandrixXmlNode);
  var
    Inc: TLandrixXmlNode;
    L: string;
  begin
    L := S8(C.LocalNameUtf8);
    if C.NamespaceUriUtf8 = SchNs then
    begin
      if L = 'let' then
        AddGlobal(C)
      else if L = 'rule' then
        P.Rules.Add(CompileRule(C))
      else if L = 'include' then
      begin
        Inc := Include(C);
        Member(Inc);
        FIncluding.Delete(FIncluding.Count - 1);
      end
      else if (L = 'title') or (L = 'p') then
        { documentation }
      else
        Fail(C, 'unexpected sch:' + L + ' in a pattern');
    end
    else if C.NamespaceUriUtf8 = XslNs then
      Unsupported(C, 'xsl:' + L + ' in a pattern is not supported')
    else if C.NamespaceUriUtf8 = '' then
      Fail(C, 'element ' + L + ' without namespace');
  end;

var
  C: TLandrixXmlNode;
begin
  if (Attr(Node, 'abstract') = 'true') or HasAttr(Node, 'is-a') then
    Unsupported(Node, 'abstract patterns are not supported (compile the preprocessed file)');
  if HasAttr(Node, 'documents') then
    Unsupported(Node, 'patterns on other documents are not supported');
  P := TPattern.Create;
  FPatterns.Add(P);
  P.Id := Attr(Node, 'id');
  C := Node.FirstChildElement;
  while C <> nil do
  begin
    Member(C);
    C := C.NextSiblingElement;
  end;
end;

function TLandrixXmlSchematronCompiler.CompileRule(Node: TLandrixXmlNode): TObject;
var
  R: TRule;
  C: TLandrixXmlNode;
  Name: TLandrixXmlUtf8;
  I: Integer;
  L: string;
begin
  if Attr(Node, 'abstract') = 'true' then
    Unsupported(Node, 'abstract rules are not supported');
  if not HasAttr(Node, 'context') then
    Fail(Node, 'a rule without context');
  if HasAttr(Node, 'subject') then
    Unsupported(Node, 'the subject of a rule is not supported');
  R := TRule.Create;
  try
    R.Context := LandrixXmlSchematronCollapse(Attr(Node, 'context'));
    R.Id := Attr(Node, 'id');
    R.Line := U(Where(Node));
    C := Node.FirstChildElement;
    while C <> nil do
    begin
      L := S8(C.LocalNameUtf8);
      if C.NamespaceUriUtf8 = SchNs then
      begin
        if L = 'let' then
        begin
          if not HasAttr(C, 'value') then
            Unsupported(C, 'a let without value is not supported');
          if HasAttr(C, 'as') then
            Unsupported(C, 'a let with "as" is not supported');
          Name := Attr(C, 'name');
          for I := 0 to Integer(Length(R.LetNames)) - 1 do
            if R.LetNames[I] = Name then
              Fail(C, 'rule variable $' + S8(Name) + ' is defined twice');
          AddUtf8(R.LetNames, Name);
          AddUtf8(R.LetValues, LandrixXmlSchematronCollapse(Attr(C, 'value')));
        end
        else if (L = 'assert') or (L = 'report') then
          R.Checks.Add(CompileCheck(C))
        else if L = 'extends' then
          Unsupported(C, 'sch:extends is not supported')
        else
          Fail(C, 'unexpected sch:' + L + ' in a rule');
      end
      else if C.NamespaceUriUtf8 = XslNs then
        Unsupported(C, 'xsl:' + L + ' in a rule is not supported')
      else if C.NamespaceUriUtf8 = '' then
        Fail(C, 'element ' + L + ' without namespace');
      C := C.NextSiblingElement;
    end;
  except
    R.Free;
    raise;
  end;
  Result := R;
end;

function TLandrixXmlSchematronCompiler.CompileCheck(Node: TLandrixXmlNode): TObject;
var
  Check: TCheck;
  Kind: string;

  procedure AddPart(const PartKind, Value: TLandrixXmlUtf8);
  var
    P: TPart;
  begin
    P := TPart.Create;
    Check.Parts.Add(P);
    P.Kind := PartKind;
    P.Value := Value;
  end;

  { text, sch:name and sch:value-of; emph, dir and span add their content }
  procedure Content(E: TLandrixXmlNode);
  var
    C: TLandrixXmlNode;
    Text: TLandrixXmlUtf8;
    L: string;
  begin
    Text := '';
    C := E.FirstChild;
    while C <> nil do
    begin
      if C.NodeType in [LandrixXmlDom.xntText, LandrixXmlDom.xntCData] then
        Text := Text + C.ValueUtf8
      else if C.NodeType = LandrixXmlDom.xntElement then
      begin
        if Text <> '' then
          AddPart('text', Text);
        Text := '';
        L := S8(C.LocalNameUtf8);
        if IsSch(C, 'name') then
          AddPart('name', Attr(C, 'path'))
        else if IsSch(C, 'value-of') then
          AddPart('value-of', LandrixXmlSchematronCollapse(Attr(C, 'select')))
        else if IsSch(C, 'emph') or IsSch(C, 'dir') or IsSch(C, 'span') then
          Content(C)
        else
          Unsupported(C, L + ' inside sch:' + Kind + ' is not supported');
      end;
      C := C.NextSibling;
    end;
    if Text <> '' then
      AddPart('text', Text);
  end;

begin
  Kind := S8(Node.LocalNameUtf8);
  if not HasAttr(Node, 'test') then
    Fail(Node, 'sch:' + Kind + ' without test');
  if HasAttr(Node, 'diagnostics') then
    Unsupported(Node, 'diagnostics are not supported');
  if HasAttr(Node, 'properties') then
    Unsupported(Node, 'properties are not supported');
  if HasAttr(Node, 'subject') then
    Unsupported(Node, 'the subject of a check is not supported');
  Check := TCheck.Create;
  try
    Check.Kind := U(Kind);
    Check.Id := Attr(Node, 'id');
    Check.Flag := Attr(Node, 'flag');
    Check.Role := Attr(Node, 'role');
    Check.Test := LandrixXmlSchematronCollapse(Attr(Node, 'test'));
    Check.Line := U(Where(Node));
    Content(Node);
  except
    Check.Free;
    raise;
  end;
  Result := Check;
end;

procedure TLandrixXmlSchematronCompiler.AddFunction(Node: TLandrixXmlNode);
var
  F: TFunction;
  C: TLandrixXmlNode;
  SeenOther: Boolean;
  I: Integer;
  Name: TLandrixXmlUtf8;

  { checked by CheckScopes with the names visible here }
  procedure CheckScope(Node: TLandrixXmlNode; const Expr: TLandrixXmlUtf8);
  var
    Check: TScopeCheck;
  begin
    Check := TScopeCheck.Create;
    FScopeChecks.Add(Check);
    Check.Node := Node;
    Check.Expression := Expr;
    Check.FunctionName := F.Name;
    Check.Names := Copy(F.Visible, 0, F.VisibleCount);
  end;

  procedure MakeVisible(const VName: TLandrixXmlUtf8);
  begin
    if F.VisibleCount = Length(F.Visible) then
      SetLength(F.Visible, 2 * F.VisibleCount + 4);
    F.Visible[F.VisibleCount] := VName;
    Inc(F.VisibleCount);
  end;

  { no text where XSLT would put it into the result }
  procedure CheckNoText(Owner: TLandrixXmlNode);
  var
    T: TLandrixXmlNode;
  begin
    T := Owner.FirstChild;
    while T <> nil do
    begin
      if (T.NodeType in [LandrixXmlDom.xntText, LandrixXmlDom.xntCData]) and not IsBlank(T.ValueUtf8) then
        Unsupported(Owner, 'text in ' + S8(Owner.NameUtf8) + ' is not supported');
      T := T.NextSibling;
    end;
  end;

  procedure Variable(V: TLandrixXmlNode);
  var
    FV: TFunctionVariable;
    Child: TLandrixXmlNode;
    VName, Value: TLandrixXmlUtf8;
  begin
    VName := Attr(V, 'name');
    if IndexOfUtf8(F.Names, VName) >= 0 then
      Fail(V, 'variable $' + S8(VName) + ' is defined twice in ' + S8(F.Name));
    AddUtf8(F.Names, VName);
    Child := V.FirstChildElement;
    if HasAttr(V, 'select') then
    begin
      if (Child <> nil) or not IsBlank(TextBelow(V)) then
        Unsupported(V, 'xsl:variable with select and content');
      Value := LandrixXmlSchematronCollapse(Attr(V, 'select'));
    end
    else if (Child <> nil) and (Child.NextSiblingElement = nil) and IsXsl(Child, 'sequence') and
      HasAttr(Child, 'select') then
    begin
      { without "as" the content would build a document node }
      if Attr(V, 'as') = '' then
        Unsupported(V, 'xsl:variable with an xsl:sequence child needs as');
      if (Child.FirstChildElement <> nil) or not IsBlank(TextBelow(Child)) then
        Unsupported(Child, 'xsl:sequence needs select and no content');
      if not IsBlank(TextBelow(V)) then
        Unsupported(V, 'xsl:variable with text around xsl:sequence');
      Value := LandrixXmlSchematronCollapse(Attr(Child, 'select'));
    end
    else if Child = nil then
    begin
      { text content: a document node with that text; atomized it is untypedAtomic }
      if IsBlank(TextBelow(V)) then
        Unsupported(V, 'xsl:variable without select and content is not supported');
      if Attr(V, 'as') <> '' then
        Unsupported(V, 'xsl:variable with text content and as is not supported');
      Value := 'xs:untypedAtomic(' + StringLiteral(TextBelow(V)) + ')';
    end
    else
    begin
      Unsupported(V, 'this form of xsl:variable is not supported');
      Value := '';
    end;
    CheckScope(V, Value);
    MakeVisible(VName);
    FV := TFunctionVariable.Create;
    F.Variables.Add(FV);
    FV.Name := VName;
    FV.AsType := Attr(V, 'as');
    FV.Value := Value;
  end;

  function Body(First: TLandrixXmlNode; Owner: TLandrixXmlNode; const What: string): TLandrixXmlUtf8; forward;

  function Choose(Ch: TLandrixXmlNode): TLandrixXmlUtf8;
  var
    W, Last: TLandrixXmlNode;
    Whens: TList;
    K: Integer;
    Test: TLandrixXmlUtf8;
  begin
    CheckNoText(Ch);
    Last := nil;
    Whens := TList.Create;
    try
      W := Ch.FirstChildElement;
      while W <> nil do
      begin
        if IsXsl(W, 'when') and (Last = nil) then
          Whens.Add(W)
        else if IsXsl(W, 'otherwise') and (Last = nil) then
          Last := W
        else
          Unsupported(Ch, 'unsupported xsl:choose');
        W := W.NextSiblingElement;
      end;
      if Whens.Count = 0 then
        Unsupported(Ch, 'unsupported xsl:choose');
      if Last <> nil then
        Result := Body(Last.FirstChildElement, Last, 'xsl:otherwise')
      else
        Result := '()';
      for K := Integer(Whens.Count) - 1 downto 0 do
      begin
        W := TLandrixXmlNode(Whens[K]);
        Test := LandrixXmlSchematronCollapse(Attr(W, 'test'));
        CheckScope(W, Test);
        Result := '(if (' + Test + ') then ' + Body(W.FirstChildElement, W, 'xsl:when') + ' else ' + Result + ')';
      end;
    finally
      Whens.Free;
    end;
  end;

  { the result expression of variables followed by one result instruction }
  function Body(First: TLandrixXmlNode; Owner: TLandrixXmlNode; const What: string): TLandrixXmlUtf8;
  var
    E: TLandrixXmlNode;
    Done: Boolean;
    Level: Integer;
  begin
    Result := '';
    Done := False;
    CheckNoText(Owner);
    { the variables of this level are visible only in it }
    Level := F.VisibleCount;
    E := First;
    while E <> nil do
    begin
      if IsXsl(E, 'variable') then
      begin
        if Done then
          Unsupported(E, 'xsl:variable after the result');
        Variable(E);
      end
      else if IsXsl(E, 'sequence') then
      begin
        if Done then
          Unsupported(E, 'more than one result instruction');
        if not HasAttr(E, 'select') or (E.FirstChildElement <> nil) or not IsBlank(TextBelow(E)) then
          Unsupported(E, 'xsl:sequence needs select and no content');
        CheckScope(E, LandrixXmlSchematronCollapse(Attr(E, 'select')));
        Result := '(' + LandrixXmlSchematronCollapse(Attr(E, 'select')) + ')';
        Done := True;
      end
      else if IsXsl(E, 'choose') then
      begin
        if Done then
          Unsupported(E, 'more than one result instruction');
        Result := Choose(E);
        Done := True;
      end
      else
        Unsupported(E, S8(E.NameUtf8) + ' is not supported in a function');
      E := E.NextSiblingElement;
    end;
    if not Done then
      Unsupported(Owner, 'no result in ' + What);
    F.VisibleCount := Level;
  end;

begin
  F := TFunction.Create;
  try
    F.Name := Attr(Node, 'name');
    F.AsType := Attr(Node, 'as');
    F.Line := U(Where(Node));
    SeenOther := False;
    C := Node.FirstChildElement;
    while (C <> nil) and IsXsl(C, 'param') do
    begin
      if HasAttr(C, 'select') or (C.FirstChildElement <> nil) or not IsBlank(TextBelow(C)) then
        Unsupported(C, 'default values of parameters are not supported');
      Name := Attr(C, 'name');
      if IndexOfUtf8(F.Names, Name) >= 0 then
        Fail(C, 'parameter $' + S8(Name) + ' is defined twice');
      AddUtf8(F.Names, Name);
      MakeVisible(Name);
      AddUtf8(F.ParamNames, Name);
      AddUtf8(F.ParamTypes, Attr(C, 'as'));
      C := C.NextSiblingElement;
    end;
    { no parameter after other instructions }
    while C <> nil do
    begin
      if IsXsl(C, 'param') and SeenOther then
        Unsupported(C, 'xsl:param after other instructions');
      SeenOther := True;
      C := C.NextSiblingElement;
    end;
    C := Node.FirstChildElement;
    while (C <> nil) and IsXsl(C, 'param') do
      C := C.NextSiblingElement;
    F.Result := Body(C, Node, 'function ' + S8(F.Name));
    for I := 0 to Integer(FFunctions.Count) - 1 do
      if (TFunction(FFunctions[I]).Name = F.Name) and
        (Length(TFunction(FFunctions[I]).ParamNames) = Length(F.ParamNames)) then
        Fail(Node, 'function ' + S8(F.Name) + '#' + IntToStr(Integer(Length(F.ParamNames))) + ' is defined twice');
  except
    F.Free;
    raise;
  end;
  FFunctions.Add(F);
end;

{ SchXslt runs all patterns unless the schema names a default phase; such
  a phase must activate every pattern with a rule. }
procedure TLandrixXmlSchematronCompiler.CheckPhases(Main: TLandrixXmlNode);
var
  Default: TLandrixXmlUtf8;
  Active: TStringList;
  D, I: Integer;
  Found: TLandrixXmlNode;

  function FindPhase(Node: TLandrixXmlNode): TLandrixXmlNode;
  var
    C: TLandrixXmlNode;
  begin
    Result := nil;
    if IsSch(Node, 'phase') and (Attr(Node, 'id') = Default) then
    begin
      Result := Node;
      Exit;
    end;
    C := Node.FirstChildElement;
    while (C <> nil) and (Result = nil) do
    begin
      Result := FindPhase(C);
      C := C.NextSiblingElement;
    end;
  end;

  procedure CollectActive(Node: TLandrixXmlNode);
  var
    C: TLandrixXmlNode;
  begin
    if IsSch(Node, 'active') then
      Active.Add(S8(Attr(Node, 'pattern')));
    C := Node.FirstChildElement;
    while C <> nil do
    begin
      CollectActive(C);
      C := C.NextSiblingElement;
    end;
  end;

begin
  Default := Attr(Main, 'defaultPhase');
  if (Default = '') or (Default = '#ALL') then
    Exit;
  Found := nil;
  D := 0;
  while (Found = nil) and (D < FDocuments.Count) do
  begin
    Found := FindPhase(TLandrixXmlDocument(FDocuments[D]).Root);
    Inc(D);
  end;
  if Found = nil then
    Fail(nil, 'the default phase ' + S8(Default) + ' is not defined');
  Active := TStringList.Create;
  try
    Active.CaseSensitive := True;
    CollectActive(Found);
    for I := 0 to Integer(FPatterns.Count) - 1 do
      if (TPattern(FPatterns[I]).Rules.Count > 0) and (Active.IndexOf(S8(TPattern(FPatterns[I]).Id)) < 0) then
        Unsupported(Found, 'the default phase ' + S8(Default) + ' does not activate pattern ' +
          S8(TPattern(FPatterns[I]).Id) + '; phases are not supported');
  finally
    Active.Free;
  end;
end;

{ Every function expression compiles with only the names visible where
  it stands (and the globals and functions): the variables lifted out of
  a choose branch are not seen outside it, as in XSLT. }
procedure TLandrixXmlSchematronCompiler.CheckScopes;
var
  I, J, K: Integer;
  Check: TScopeCheck;
  Context: TLandrixXmlXPathStaticContext;
  F: TFunction;
  Prefix, Local, Uri: TLandrixXmlUtf8;
begin
  for I := 0 to Integer(FScopeChecks.Count) - 1 do
  begin
    Check := TScopeCheck(FScopeChecks[I]);
    Context := TLandrixXmlXPathStaticContext.Create;
    try
      for J := 0 to Integer(Length(FNsPrefixes)) - 1 do
        Context.AddNamespace(FNsPrefixes[J], FNsUris[J]);
      for J := 0 to Integer(FGlobals.Count) - 1 do
        Context.DeclareVariable(TGlobal(FGlobals[J]).Name);
      for J := 0 to Integer(Length(Check.Names)) - 1 do
        Context.DeclareVariable(Check.Names[J]);
      for J := 0 to Integer(FFunctions.Count) - 1 do
      begin
        F := TFunction(FFunctions[J]);
        Prefix := '';
        Local := F.Name;
        for K := 1 to Length(F.Name) do
          if F.Name[K] = ':' then
          begin
            Prefix := Copy(F.Name, 1, K - 1);
            Local := Copy(F.Name, K + 1, MaxInt);
            Break;
          end;
        { a prefix that is not declared: the loader reports it }
        if Context.LookupNamespace(Prefix, Uri) then
          Context.DeclareFunction(Uri, Local, Integer(Length(F.ParamNames)));
      end;
      try
        TLandrixXmlXPathExpression.Create(Check.Expression, Context).Free;
      except
        on E: ELandrixXmlXPathError do
          if E.XPathCode = 'XPST0008' then
            Unsupported(Check.Node, Copy(E.Message, Length(E.XPathCode) + 3, MaxInt) + ' here in ' +
              S8(Check.FunctionName) + ' (out of its scope)')
          else
            raise ELandrixXmlXPathError.CreateXPath(E.XPathCode, 'Schematron: ' + Where(Check.Node) + ': ' +
              Copy(E.Message, Length(E.XPathCode) + 3, MaxInt));
      end;
    finally
      Context.Free;
    end;
  end;
end;

procedure TLandrixXmlSchematronCompiler.ApplyOverrides;
var
  I, P, R, K, Count: Integer;
  Check, Hit: TCheck;
  Rule: TRule;
begin
  for I := 0 to Integer(Length(FOverrideIds)) - 1 do
  begin
    Count := 0;
    Hit := nil;
    for P := 0 to Integer(FPatterns.Count) - 1 do
      for R := 0 to Integer(TPattern(FPatterns[P]).Rules.Count) - 1 do
      begin
        Rule := TRule(TPattern(FPatterns[P]).Rules[R]);
        for K := 0 to Integer(Rule.Checks.Count) - 1 do
        begin
          Check := TCheck(Rule.Checks[K]);
          if Check.Id = FOverrideIds[I] then
          begin
            Inc(Count);
            Hit := Check;
          end;
        end;
      end;
    if Count <> 1 then
      Fail(nil, 'override ' + S8(FOverrideIds[I]) + ': ' + IntToStr(Count) + ' checks have this id');
    if Hit.Test <> LandrixXmlSchematronCollapse(FOverrideOriginals[I]) then
      Fail(nil, 'override ' + S8(FOverrideIds[I]) + ': the test of the source is "' + S8(Hit.Test) +
        '", not the expected one');
    Hit.Original := Hit.Test;
    Hit.HasOriginal := True;
    Hit.Test := LandrixXmlSchematronCollapse(FOverrideTests[I]);
  end;
end;

function TLandrixXmlSchematronCompiler.Write(Main: TLandrixXmlNode; const Sha256, FileName: string):
  TLandrixXmlDocument;
var
  Doc: TLandrixXmlDocument;
  Root, E, X, T: TLandrixXmlNode;
  I, J, K, Q: Integer;
  P: TPattern;
  R: TRule;
  Check: TCheck;
  F: TFunction;
  Part: TPart;
  Title: TLandrixXmlUtf8;
begin
  Doc := TLandrixXmlDocument.Create;
  try
    Root := Doc.AddElement(RulesNs, '', 'rules');
    Root.SetAttributeUtf8('format', '1');
    Root.SetAttributeUtf8('source', U(ExtractFileName(FileName)));
    Root.SetAttributeUtf8('sha256', U(Sha256));
    Title := '';
    T := Main.FirstChildElement;
    while T <> nil do
    begin
      if IsSch(T, 'title') then
      begin
        Title := LandrixXmlSchematronCollapse(TextBelow(T));
        Break;
      end;
      T := T.NextSiblingElement;
    end;
    Root.SetAttributeUtf8('title', Title);
    if FUrl <> '' then
      Root.SetAttributeUtf8('url', FUrl);
    for I := 0 to Integer(Length(FNsPrefixes)) - 1 do
    begin
      E := Root.AddElement(RulesNs, '', 'ns');
      E.SetAttributeUtf8('prefix', FNsPrefixes[I]);
      E.SetAttributeUtf8('uri', FNsUris[I]);
    end;
    for I := 0 to Integer(FGlobals.Count) - 1 do
    begin
      E := Root.AddElement(RulesNs, '', 'let');
      E.SetAttributeUtf8('name', TGlobal(FGlobals[I]).Name);
      E.SetAttributeUtf8('value', TGlobal(FGlobals[I]).Value);
      E.SetAttributeUtf8('line', TGlobal(FGlobals[I]).Line);
    end;
    for I := 0 to Integer(FFunctions.Count) - 1 do
    begin
      F := TFunction(FFunctions[I]);
      E := Root.AddElement(RulesNs, '', 'function');
      E.SetAttributeUtf8('name', F.Name);
      E.SetAttributeUtf8('as', F.AsType);
      E.SetAttributeUtf8('line', F.Line);
      for J := 0 to Integer(Length(F.ParamNames)) - 1 do
      begin
        X := E.AddElement(RulesNs, '', 'param');
        X.SetAttributeUtf8('name', F.ParamNames[J]);
        X.SetAttributeUtf8('as', F.ParamTypes[J]);
      end;
      for J := 0 to Integer(F.Variables.Count) - 1 do
      begin
        X := E.AddElement(RulesNs, '', 'variable');
        X.SetAttributeUtf8('name', TFunctionVariable(F.Variables[J]).Name);
        X.SetAttributeUtf8('as', TFunctionVariable(F.Variables[J]).AsType);
        X.SetAttributeUtf8('value', TFunctionVariable(F.Variables[J]).Value);
      end;
      X := E.AddElement(RulesNs, '', 'result');
      X.SetAttributeUtf8('value', F.Result);
    end;
    for I := 0 to Integer(FPatterns.Count) - 1 do
    begin
      P := TPattern(FPatterns[I]);
      if P.Rules.Count = 0 then
        Continue;
      E := Root.AddElement(RulesNs, '', 'pattern');
      E.SetAttributeUtf8('id', P.Id);
      for J := 0 to Integer(P.Rules.Count) - 1 do
      begin
        R := TRule(P.Rules[J]);
        X := E.AddElement(RulesNs, '', 'rule');
        X.SetAttributeUtf8('context', R.Context);
        X.SetAttributeUtf8('id', R.Id);
        X.SetAttributeUtf8('line', R.Line);
        for K := 0 to Integer(Length(R.LetNames)) - 1 do
        begin
          T := X.AddElement(RulesNs, '', 'let');
          T.SetAttributeUtf8('name', R.LetNames[K]);
          T.SetAttributeUtf8('value', R.LetValues[K]);
        end;
        for K := 0 to Integer(R.Checks.Count) - 1 do
        begin
          Check := TCheck(R.Checks[K]);
          T := X.AddElement(RulesNs, '', Check.Kind);
          T.SetAttributeUtf8('id', Check.Id);
          T.SetAttributeUtf8('flag', Check.Flag);
          T.SetAttributeUtf8('role', Check.Role);
          T.SetAttributeUtf8('test', Check.Test);
          T.SetAttributeUtf8('line', Check.Line);
          if Check.HasOriginal then
            T.SetAttributeUtf8('original', Check.Original);
          for Q := 0 to Integer(Check.Parts.Count) - 1 do
          begin
            Part := TPart(Check.Parts[Q]);
            if Part.Kind = 'text' then
              T.AddElement(RulesNs, '', 'text').AddTextUtf8(Part.Value)
            else if Part.Kind = 'name' then
              T.AddElement(RulesNs, '', 'name').SetAttributeUtf8('path', Part.Value)
            else
              T.AddElement(RulesNs, '', 'value-of').SetAttributeUtf8('select', Part.Value);
          end;
        end;
      end;
    end;
  except
    Doc.Free;
    raise;
  end;
  Result := Doc;
end;

function TLandrixXmlSchematronCompiler.CompileFile(const FileName: string): TLandrixXmlDocument;
var
  Path, QueryBinding: string;
  Main: TLandrixXmlNode;
  Bytes: TLandrixXmlUtf8;
  Sha: string;
begin
  Reset;
  try
    Path := ExpandFileName(FileName);
    Bytes := FileBytes(Path);
    if Bytes = '' then
      Sha := LandrixXmlSha256Hex(Pointer(nil)^, 0)
    else
      Sha := LandrixXmlSha256Hex(Bytes[1], Length(Bytes));
    FIncluding.Add(Path);
    Main := LoadDocument(Path).Root;
    if not IsSch(Main, 'schema') then
      Fail(nil, 'not a Schematron schema: ' + FileName);
    QueryBinding := S8(Attr(Main, 'queryBinding'));
    if QueryBinding = '' then
      QueryBinding := 'xslt';
    if (QueryBinding <> 'xslt2') and (QueryBinding <> 'xslt3') then
      Unsupported(Main, 'queryBinding "' + QueryBinding + '" is not supported');
    Walk(Main);
    CheckScopes;
    CheckPhases(Main);
    ApplyOverrides;
    Result := Write(Main, Sha, Path);
  finally
    Reset;
  end;
end;

end.
