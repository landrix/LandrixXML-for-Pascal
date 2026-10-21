{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Loads XML Schema 1.0 documents into a TLandrixXmlXsdSchemaSet: include,
  import and redefine (also of schema documents without a target
  namespace, which take the namespace of the including document), global
  and local declarations, named and anonymous types, model groups and
  attribute groups (expanded), simple and complex content derived by
  extension or restriction, wildcards and identity constraints.

  Schema locations are resolved by a TLandrixXmlXsdResolver: an explicit
  catalog first, then the location relative to the including document.
  There is no network access and no search by file name; an import that
  cannot be resolved is skipped (as Xerces does when it cannot fetch it),
  so a reference into it fails with a message naming the import.

  The derivation of a restricted type is not checked against its base:
  the content and attributes are taken as written (the target schemas
  are valid for Xerces). Constructs the validator does not support raise
  ELandrixXmlError with xecUnsupported and the file and line, also when
  they are declared but not used: xs:all, xs:list, xs:notation,
  substitution groups, abstract elements, the extension of xs:anyType,
  and the built-in types LandrixXmlXsdTypes lacks. Other schema errors
  raise xecSchema. }

unit LandrixXmlXsdSchemaLoader;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  Contnrs,
  LandrixXmlBase,
  LandrixXmlDom,
  LandrixXmlXsdTypes,
  LandrixXmlXsdContent,
  LandrixXmlXsdSchema;

type
  TLandrixXmlXsdResolver = class
  private
    FNamespaces: TLandrixXmlUtf8Array;
    FNamespaceFiles: TStringList;
    FLocations: TLandrixXmlUtf8Array;
    FLocationFiles: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    { An import of NamespaceUri reads FileName, whatever its location. }
    procedure AddNamespace(const NamespaceUri: TLandrixXmlUtf8; const FileName: string);
    { A schemaLocation written exactly as Location reads FileName. }
    procedure AddLocation(const Location: TLandrixXmlUtf8; const FileName: string);
    { The file to read, or '' if there is none. BaseFile is the including
      schema document; NamespaceUri the namespace of an import (IsImport).
      The default: the catalog, then Location (percent-decoded) relative
      to BaseFile if that file exists; locations with a URI scheme such as
      http: give ''. }
    function Resolve(const BaseFile: string; const Location, NamespaceUri: TLandrixXmlUtf8;
      IsImport: Boolean): string; virtual;
  end;

{ Loads the schema whose entry document is FileName. Resolver may be nil
  (the default resolution). The caller owns the result. }
function LandrixXmlXsdLoadSchema(const FileName: string;
  Resolver: TLandrixXmlXsdResolver = nil): TLandrixXmlXsdSchemaSet;

implementation

{ ---------------------------------------------------------------------- }
{ TLandrixXmlXsdResolver                                                 }
{ ---------------------------------------------------------------------- }

constructor TLandrixXmlXsdResolver.Create;
begin
  inherited Create;
  FNamespaceFiles := TStringList.Create;
  FLocationFiles := TStringList.Create;
end;

destructor TLandrixXmlXsdResolver.Destroy;
begin
  FNamespaceFiles.Free;
  FLocationFiles.Free;
  inherited Destroy;
end;

procedure TLandrixXmlXsdResolver.AddNamespace(const NamespaceUri: TLandrixXmlUtf8; const FileName: string);
begin
  SetLength(FNamespaces, Length(FNamespaces) + 1);
  FNamespaces[High(FNamespaces)] := NamespaceUri;
  FNamespaceFiles.Add(FileName);
end;

procedure TLandrixXmlXsdResolver.AddLocation(const Location: TLandrixXmlUtf8; const FileName: string);
begin
  SetLength(FLocations, Length(FLocations) + 1);
  FLocations[High(FLocations)] := Location;
  FLocationFiles.Add(FileName);
end;

function HexDigit(C: AnsiChar): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function PercentDecoded(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  I, N, Hi, Lo: Integer;
begin
  Result := S;
  N := 0;
  I := 1;
  while I <= Length(S) do
  begin
    Inc(N);
    if (S[I] = '%') and (I + 2 <= Length(S)) then
    begin
      Hi := HexDigit(AnsiChar(S[I + 1]));
      Lo := HexDigit(AnsiChar(S[I + 2]));
      if (Hi >= 0) and (Lo >= 0) then
      begin
        Result[N] := AnsiChar(Hi * 16 + Lo);
        Inc(I, 3);
        Continue;
      end;
    end;
    Result[N] := S[I];
    Inc(I);
  end;
  SetLength(Result, N);
end;

function HasScheme(const S: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to Length(S) do
    case S[I] of
      'a'..'z', 'A'..'Z', '0'..'9', '+', '-', '.':
        ;
      ':':
        begin
          { a drive letter is not a scheme }
          Result := I > 2;
          Exit;
        end;
    else
      Exit;
    end;
end;

function TLandrixXmlXsdResolver.Resolve(const BaseFile: string;
  const Location, NamespaceUri: TLandrixXmlUtf8; IsImport: Boolean): string;
var
  I: Integer;
  Path: string;
begin
  Result := '';
  if IsImport then
    for I := 0 to Integer(Length(FNamespaces)) - 1 do
      if FNamespaces[I] = NamespaceUri then
      begin
        Result := FNamespaceFiles[I];
        Exit;
      end;
  for I := 0 to Integer(Length(FLocations)) - 1 do
    if FLocations[I] = Location then
    begin
      Result := FLocationFiles[I];
      Exit;
    end;
  if (Location = '') or HasScheme(Location) then
    Exit;
  Path := LandrixXmlUtf8ToString(PercentDecoded(Location));
  for I := 1 to Length(Path) do
    if (Path[I] = '/') or (Path[I] = '\') then
      Path[I] := PathDelim;
  { an absolute path ("/x.xsd") is not relative to the including file }
  if Path[1] = PathDelim then
    Path := ExpandFileName(Path)
  else
    Path := ExpandFileName(ExtractFilePath(BaseFile) + Path);
  if FileExists(Path) then
    Result := Path;
end;

{ ---------------------------------------------------------------------- }
{ Loader                                                                 }
{ ---------------------------------------------------------------------- }

type
  TSchemaDoc = class
    FileName: string;
    Root: TLandrixXmlNode;
    TargetNamespace: TLandrixXmlUtf8;
    Chameleon: Boolean;
    ElementQualified: Boolean;
    AttributeQualified: Boolean;
  end;

  TPendingKind = (pkElement, pkAttribute, pkComplexType, pkSimpleType, pkGroup, pkAttributeGroup);
  TPendingState = (psNew, psResolving, psDone);

  { A global declaration or definition found in a schema document, built
    on first use. Original is the component a redefinition replaces. }
  TPending = class
    Kind: TPendingKind;
    Node: TLandrixXmlNode;
    Doc: TSchemaDoc;
    NamespaceUri: TLandrixXmlUtf8;
    Name: TLandrixXmlUtf8;
    Original: TPending;
    Component: TObject;
    State: TPendingState;
  end;

  { An attribute use being collected, or a prohibition. }
  TAttributeItem = class
    Decl: TLandrixXmlXsdAttributeDecl;
    Required: Boolean;
    Prohibited: Boolean;
    ValueConstraint: TLandrixXmlXsdValueConstraint;
    ConstraintValue: TLandrixXmlUtf8;
  end;

  TKeyRefFixup = class
    Constraint: TLandrixXmlXsdIdentityConstraint;
    NamespaceUri: TLandrixXmlUtf8;
    Name: TLandrixXmlUtf8;
    FileName: string;
    Line: Integer;
  end;

  TLoader = class
  private
    FSet: TLandrixXmlXsdSchemaSet;
    FResolver: TLandrixXmlXsdResolver;
    FDomFiles: TStringList;
    FDocs: TObjectList;
    FDocMap: TLandrixXmlXsdNameMap;
    FPendings: TObjectList;
    FMaps: array[TPendingKind] of TLandrixXmlXsdNameMap;
    FLocalCache: TLandrixXmlXsdNameMap;
    FIdentity: TLandrixXmlXsdNameMap;
    FFixups: TObjectList;
    FSkippedImports: TStringList;
    FCurrent: TPending;
    procedure Fail(Doc: TSchemaDoc; Node: TLandrixXmlNode; const Msg: string);
    procedure Unsupported(Doc: TSchemaDoc; Node: TLandrixXmlNode; const What: string);
    function LoadDom(const FileName: string): TLandrixXmlDocument;
    function LoadDocument(const FileName: string; Including: TSchemaDoc; IsImport: Boolean;
      const ImportNamespace: TLandrixXmlUtf8; Node: TLandrixXmlNode): TSchemaDoc;
    procedure Collect(Doc: TSchemaDoc; Node: TLandrixXmlNode; Kind: TPendingKind);
    procedure ApplyRedefine(Doc: TSchemaDoc; Redefine: TLandrixXmlNode);
    function ResolveQName(Doc: TSchemaDoc; Node: TLandrixXmlNode; const Value: TLandrixXmlUtf8;
      out NamespaceUri, LocalName: TLandrixXmlUtf8): Boolean;
    function QNameAttr(Doc: TSchemaDoc; Node: TLandrixXmlNode; const AttrName: TLandrixXmlUtf8;
      out NamespaceUri, LocalName: TLandrixXmlUtf8): Boolean;
    function FindPending(Kind: TPendingKind; const NamespaceUri, LocalName: TLandrixXmlUtf8;
      SelfOwner: TLandrixXmlNode = nil): TPending;
    function MissingText(const What: string; const NamespaceUri, LocalName: TLandrixXmlUtf8): string;
    function LocalKey(Doc: TSchemaDoc; Node: TLandrixXmlNode): TLandrixXmlUtf8;
    { components }
    function ResolveElement(P: TPending): TLandrixXmlXsdElementDecl;
    function ResolveAttribute(P: TPending): TLandrixXmlXsdAttributeDecl;
    function ResolveComplexType(P: TPending; NeedComplete: Boolean): TLandrixXmlXsdComplexType;
    function ResolveSimpleType(P: TPending): TLandrixXmlXsdSimpleType;
    procedure ResolveTypeRef(Doc: TSchemaDoc; Node: TLandrixXmlNode; const AttrName: TLandrixXmlUtf8;
      out Simple: TLandrixXmlXsdSimpleType; out Complex: TLandrixXmlXsdComplexType; out Pending: TPending);
    function SimpleTypeRef(Doc: TSchemaDoc; Node: TLandrixXmlNode; const NamespaceUri,
      LocalName: TLandrixXmlUtf8; SelfOwner: TLandrixXmlNode = nil): TLandrixXmlXsdSimpleType;
    function BuildElement(Doc: TSchemaDoc; Node: TLandrixXmlNode; Global: Boolean;
      P: TPending): TLandrixXmlXsdElementDecl;
    function LocalElement(Doc: TSchemaDoc; Node: TLandrixXmlNode): TLandrixXmlXsdElementDecl;
    function BuildAttribute(Doc: TSchemaDoc; Node: TLandrixXmlNode; Global: Boolean;
      P: TPending): TLandrixXmlXsdAttributeDecl;
    function BuildSimpleType(Doc: TSchemaDoc; Node: TLandrixXmlNode; const Name: TLandrixXmlUtf8;
      P: TPending): TLandrixXmlXsdSimpleType;
    procedure AddFacets(Doc: TSchemaDoc; Restriction: TLandrixXmlNode; T: TLandrixXmlXsdSimpleType);
    function CreateComplexType(Doc: TSchemaDoc; Node: TLandrixXmlNode; const Name: TLandrixXmlUtf8;
      P: TPending): TLandrixXmlXsdComplexType;
    procedure FillComplexType(T: TLandrixXmlXsdComplexType; Doc: TSchemaDoc; Node: TLandrixXmlNode;
      P: TPending);
    function BuildComplexType(Doc: TSchemaDoc; Node: TLandrixXmlNode): TLandrixXmlXsdComplexType;
    function WildcardFor(Doc: TSchemaDoc; Node: TLandrixXmlNode): TLandrixXmlXsdWildcard;
    function CombineWildcards(A, B: TLandrixXmlXsdWildcard; Union: Boolean; Doc: TSchemaDoc;
      Node: TLandrixXmlNode): TLandrixXmlXsdWildcard;
    function BuildParticle(Doc: TSchemaDoc; Node: TLandrixXmlNode): TLandrixXmlXsdParticle;
    function BuildCompositor(Doc: TSchemaDoc; Node: TLandrixXmlNode; MinOccurs,
      MaxOccurs: Integer): TLandrixXmlXsdParticle;
    function ParticleOfChildren(Doc: TSchemaDoc; Parent: TLandrixXmlNode): TLandrixXmlXsdParticle;
    function EffectiveParticle(Doc: TSchemaDoc; TypeNode: TLandrixXmlNode): TLandrixXmlXsdParticle;
    procedure CollectAttributes(Doc: TSchemaDoc; Parent: TLandrixXmlNode; Items: TObjectList;
      var Wildcard: TLandrixXmlXsdWildcard);
    function BuildIdentity(Doc: TSchemaDoc; Node: TLandrixXmlNode): TLandrixXmlXsdIdentityConstraint;
    function ParsePaths(Doc: TSchemaDoc; Node: TLandrixXmlNode; const Expr: TLandrixXmlUtf8;
      IsField: Boolean): TLandrixXmlXsdPaths;
    procedure ResolveAll;
  public
    constructor Create(Resolver: TLandrixXmlXsdResolver);
    destructor Destroy; override;
    function Load(const FileName: string): TLandrixXmlXsdSchemaSet;
  end;

{ --- helpers ----------------------------------------------------------- }

function IsXs(Node: TLandrixXmlNode; const LocalName: TLandrixXmlUtf8): Boolean;
begin
  Result := (Node <> nil) and Node.IsElement and (Node.LocalNameUtf8 = LocalName) and
    (Node.NamespaceUriUtf8 = LandrixXmlXsdNamespace);
end;

function IsSpace(C: AnsiChar): Boolean;
begin
  Result := (C = ' ') or (C = #9) or (C = #10) or (C = #13);
end;

function Trimmed(const S: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  First, Last: Integer;
begin
  First := 1;
  Last := Length(S);
  while (First <= Last) and IsSpace(AnsiChar(S[First])) do
    Inc(First);
  while (Last >= First) and IsSpace(AnsiChar(S[Last])) do
    Dec(Last);
  Result := Copy(S, First, Last - First + 1);
end;

function Attr(Node: TLandrixXmlNode; const Name: TLandrixXmlUtf8; out Value: TLandrixXmlUtf8): Boolean;
begin
  Result := Node.TryAttributeValueUtf8('', Name, Value);
end;

function AttrTrimmed(Node: TLandrixXmlNode; const Name: TLandrixXmlUtf8; out Value: TLandrixXmlUtf8): Boolean;
begin
  Result := Node.TryAttributeValueUtf8('', Name, Value);
  if Result then
    Value := Trimmed(Value);
end;

function BoolAttr(Node: TLandrixXmlNode; const Name: TLandrixXmlUtf8): Boolean;
var
  Value: TLandrixXmlUtf8;
begin
  Result := AttrTrimmed(Node, Name, Value) and ((Value = 'true') or (Value = '1'));
end;

function Esc(const S: TLandrixXmlUtf8): string;
begin
  Result := LandrixXmlEscapeForMessage(S, 200);
end;

function QualifiedText(const NamespaceUri, LocalName: TLandrixXmlUtf8): string;
begin
  if NamespaceUri = '' then
    Result := Esc(LocalName)
  else
    Result := '{' + Esc(NamespaceUri) + '}' + Esc(LocalName);
end;

{ Xerces' name for an anonymous type: #AnonType_ followed by the name
  attributes of the enclosing elements up to the schema element. }
function AnonymousTypeName(Node: TLandrixXmlNode): TLandrixXmlUtf8;
var
  Parent: TLandrixXmlNode;
  Value: TLandrixXmlUtf8;
begin
  Result := '#AnonType_';
  Parent := Node.Parent;
  while (Parent <> nil) and Parent.IsElement and not IsXs(Parent, 'schema') do
  begin
    if Attr(Parent, 'name', Value) then
      Result := Result + Value;
    Parent := Parent.Parent;
  end;
end;

function PointerKey(P: Pointer): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(Format('%p', [P]));
end;

{ --- TLoader ------------------------------------------------------------ }

constructor TLoader.Create(Resolver: TLandrixXmlXsdResolver);
var
  K: TPendingKind;
begin
  inherited Create;
  FResolver := Resolver;
  FDomFiles := TStringList.Create;
  FDomFiles.CaseSensitive := True;
  FDocs := TObjectList.Create(True);
  FDocMap := TLandrixXmlXsdNameMap.Create;
  FPendings := TObjectList.Create(True);
  for K := Low(TPendingKind) to High(TPendingKind) do
    FMaps[K] := TLandrixXmlXsdNameMap.Create;
  FLocalCache := TLandrixXmlXsdNameMap.Create;
  FIdentity := TLandrixXmlXsdNameMap.Create;
  FFixups := TObjectList.Create(True);
  FSkippedImports := TStringList.Create;
end;

destructor TLoader.Destroy;
var
  I: Integer;
  K: TPendingKind;
begin
  for I := 0 to Integer(FDomFiles.Count) - 1 do
    FDomFiles.Objects[I].Free;
  FDomFiles.Free;
  FDocs.Free;
  FDocMap.Free;
  FPendings.Free;
  for K := Low(TPendingKind) to High(TPendingKind) do
    FMaps[K].Free;
  FLocalCache.Free;
  FIdentity.Free;
  FFixups.Free;
  FSkippedImports.Free;
  FSet.Free;
  inherited Destroy;
end;

procedure TLoader.Fail(Doc: TSchemaDoc; Node: TLandrixXmlNode; const Msg: string);
var
  Where: string;
begin
  Where := '';
  if Doc <> nil then
  begin
    Where := Doc.FileName;
    if (Node <> nil) and (Node.Line > 0) then
      Where := Where + ':' + IntToStr(Node.Line);
    Where := ' in ' + Where;
  end;
  raise ELandrixXmlError.CreateCode(xecSchema, 'XML Schema: ' + Msg + Where);
end;

procedure TLoader.Unsupported(Doc: TSchemaDoc; Node: TLandrixXmlNode; const What: string);
var
  Where: string;
begin
  Where := Doc.FileName;
  if (Node <> nil) and (Node.Line > 0) then
    Where := Where + ':' + IntToStr(Node.Line);
  raise ELandrixXmlError.CreateCode(xecUnsupported, 'XML Schema: not supported: ' + What + ' in ' + Where);
end;

function TLoader.LoadDom(const FileName: string): TLandrixXmlDocument;
var
  I: Integer;
begin
  I := FDomFiles.IndexOf(FileName);
  if I >= 0 then
  begin
    Result := TLandrixXmlDocument(FDomFiles.Objects[I]);
    Exit;
  end;
  Result := TLandrixXmlDocument.Create;
  try
    Result.LoadFromFile(FileName);
  except
    on E: ELandrixXmlError do
    begin
      Result.Free;
      raise ELandrixXmlError.CreateCode(E.Code, 'XML Schema document ' + FileName + ': ' + E.Message);
    end;
    on E: Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
  FDomFiles.AddObject(FileName, Result);
end;

function TLoader.Load(const FileName: string): TLandrixXmlXsdSchemaSet;
var
  Path: string;
begin
  FSet := TLandrixXmlXsdSchemaSet.Create;
  Path := ExpandFileName(FileName);
  if not FileExists(Path) then
    raise ELandrixXmlError.CreateCode(xecSchema, 'XML Schema document not found: ' + FileName);
  FSet.EntryFile := Path;
  LoadDocument(Path, nil, False, '', nil);
  ResolveAll;
  Result := FSet;
  FSet := nil;
end;

function TLoader.LoadDocument(const FileName: string; Including: TSchemaDoc; IsImport: Boolean;
  const ImportNamespace: TLandrixXmlUtf8; Node: TLandrixXmlNode): TSchemaDoc;
var
  Dom: TLandrixXmlDocument;
  Root, Child: TLandrixXmlNode;
  Tns, Effective, Value, Location, Ns: TLandrixXmlUtf8;
  HasTns, HasNs: Boolean;
  Key: TLandrixXmlUtf8;
  Name: TLandrixXmlUtf8;
  Target: string;
  Redefined: TSchemaDoc;
begin
  Dom := LoadDom(FileName);
  Root := Dom.Root;
  if not IsXs(Root, 'schema') then
    Fail(Including, Node, FileName + ' is not an XML Schema document');
  HasTns := Attr(Root, 'targetNamespace', Tns);
  if not HasTns then
    Tns := '';
  if Including = nil then
    Effective := Tns
  else if IsImport then
  begin
    if Tns <> ImportNamespace then
      Fail(Including, Node, 'the imported document ' + FileName + ' has the target namespace "' +
        Esc(Tns) + '", not "' + Esc(ImportNamespace) + '"');
    Effective := Tns;
  end
  else
  begin
    if HasTns and (Tns <> Including.TargetNamespace) then
      Fail(Including, Node, 'the included document ' + FileName + ' has another target namespace');
    Effective := Including.TargetNamespace;
  end;
  Key := Effective + #9 + LandrixXmlStringToUtf8(FileName);
  Result := TSchemaDoc(FDocMap.Find('', Key));
  if Result <> nil then
    Exit;
  Result := TSchemaDoc.Create;
  FDocs.Add(Result);
  FDocMap.Add('', Key, Result);
  if FSet.Files.IndexOf(FileName) < 0 then
    FSet.Files.Add(FileName);
  Result.FileName := FileName;
  Result.Root := Root;
  Result.TargetNamespace := Effective;
  Result.Chameleon := not HasTns and (Effective <> '');
  Result.ElementQualified := AttrTrimmed(Root, 'elementFormDefault', Value) and (Value = 'qualified');
  Result.AttributeQualified := AttrTrimmed(Root, 'attributeFormDefault', Value) and (Value = 'qualified');
  Child := Root.FirstChildElement;
  while Child <> nil do
  begin
    if Child.NamespaceUriUtf8 <> LandrixXmlXsdNamespace then
      Fail(Result, Child, 'unexpected element "' + Esc(Child.NameUtf8) + '"');
    Name := Child.LocalNameUtf8;
    if Name = 'include' then
    begin
      if not AttrTrimmed(Child, 'schemaLocation', Location) then
        Fail(Result, Child, 'include without schemaLocation');
      Target := FResolver.Resolve(Result.FileName, Location, '', False);
      if Target = '' then
        Fail(Result, Child, 'cannot resolve the include of "' + Esc(Location) + '"');
      LoadDocument(Target, Result, False, '', Child);
    end
    else if Name = 'import' then
    begin
      HasNs := AttrTrimmed(Child, 'namespace', Ns);
      if not HasNs then
        Ns := '';
      if not AttrTrimmed(Child, 'schemaLocation', Location) then
        Location := '';
      Target := FResolver.Resolve(Result.FileName, Location, Ns, True);
      if Target = '' then
        FSkippedImports.Add(Esc(Ns) + ' (' + Esc(Location) + ', ' + Result.FileName + ':' +
          IntToStr(Child.Line) + ')')
      else
        LoadDocument(Target, Result, True, Ns, Child);
    end
    else if Name = 'redefine' then
    begin
      if not AttrTrimmed(Child, 'schemaLocation', Location) then
        Fail(Result, Child, 'redefine without schemaLocation');
      Target := FResolver.Resolve(Result.FileName, Location, '', False);
      if Target = '' then
        Fail(Result, Child, 'cannot resolve the redefine of "' + Esc(Location) + '"');
      Redefined := LoadDocument(Target, Result, False, '', Child);
      if Redefined <> nil then
        ApplyRedefine(Result, Child);
    end
    else if Name = 'annotation' then
      { ignored }
    else if Name = 'element' then
      Collect(Result, Child, pkElement)
    else if Name = 'attribute' then
      Collect(Result, Child, pkAttribute)
    else if Name = 'complexType' then
      Collect(Result, Child, pkComplexType)
    else if Name = 'simpleType' then
      Collect(Result, Child, pkSimpleType)
    else if Name = 'group' then
      Collect(Result, Child, pkGroup)
    else if Name = 'attributeGroup' then
      Collect(Result, Child, pkAttributeGroup)
    else if Name = 'notation' then
      Unsupported(Result, Child, 'xs:notation')
    else
      Fail(Result, Child, 'unexpected element "' + Esc(Child.NameUtf8) + '"');
    Child := Child.NextSiblingElement;
  end;
end;

procedure TLoader.Collect(Doc: TSchemaDoc; Node: TLandrixXmlNode; Kind: TPendingKind);
var
  P: TPending;
  Name: TLandrixXmlUtf8;
  Clash: Boolean;
begin
  if not AttrTrimmed(Node, 'name', Name) or (Name = '') then
    Fail(Doc, Node, 'a global declaration without a name');
  { simple and complex types share their symbol space }
  Clash := False;
  if Kind = pkComplexType then
    Clash := FMaps[pkSimpleType].Find(Doc.TargetNamespace, Name) <> nil
  else if Kind = pkSimpleType then
    Clash := FMaps[pkComplexType].Find(Doc.TargetNamespace, Name) <> nil;
  P := TPending.Create;
  FPendings.Add(P);
  P.Kind := Kind;
  P.Node := Node;
  P.Doc := Doc;
  P.NamespaceUri := Doc.TargetNamespace;
  P.Name := Name;
  if Clash or not FMaps[Kind].Add(Doc.TargetNamespace, Name, P) then
    Fail(Doc, Node, 'duplicate global declaration of ' + QualifiedText(Doc.TargetNamespace, Name));
end;

procedure TLoader.ApplyRedefine(Doc: TSchemaDoc; Redefine: TLandrixXmlNode);
var
  Child: TLandrixXmlNode;
  Kind: TPendingKind;
  Name: TLandrixXmlUtf8;
  Original, P: TPending;
begin
  Child := Redefine.FirstChildElement;
  while Child <> nil do
  begin
    if IsXs(Child, 'annotation') then
    begin
      Child := Child.NextSiblingElement;
      Continue;
    end;
    if IsXs(Child, 'simpleType') then
      Kind := pkSimpleType
    else if IsXs(Child, 'complexType') then
      Kind := pkComplexType
    else if IsXs(Child, 'group') then
      Kind := pkGroup
    else if IsXs(Child, 'attributeGroup') then
      Kind := pkAttributeGroup
    else
    begin
      Fail(Doc, Child, 'unexpected element "' + Esc(Child.NameUtf8) + '" in xs:redefine');
      Kind := pkGroup;
    end;
    if not AttrTrimmed(Child, 'name', Name) then
      Fail(Doc, Child, 'a redefinition without a name');
    Original := TPending(FMaps[Kind].Find(Doc.TargetNamespace, Name));
    if Original = nil then
      Fail(Doc, Child, 'the redefined component ' + QualifiedText(Doc.TargetNamespace, Name) +
        ' does not exist');
    P := TPending.Create;
    FPendings.Add(P);
    P.Kind := Kind;
    P.Node := Child;
    P.Doc := Doc;
    P.NamespaceUri := Doc.TargetNamespace;
    P.Name := Name;
    P.Original := Original;
    FMaps[Kind].Put(Doc.TargetNamespace, Name, P);
    Child := Child.NextSiblingElement;
  end;
end;

function TLoader.ResolveQName(Doc: TSchemaDoc; Node: TLandrixXmlNode; const Value: TLandrixXmlUtf8;
  out NamespaceUri, LocalName: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
  Prefix, S: TLandrixXmlUtf8;
begin
  S := Trimmed(Value);
  Prefix := '';
  LocalName := S;
  for I := 1 to Length(S) do
    if S[I] = ':' then
    begin
      Prefix := Copy(S, 1, I - 1);
      LocalName := Copy(S, I + 1, MaxInt);
      Break;
    end;
  if not Node.LookupNamespace(Prefix, NamespaceUri) then
  begin
    if Prefix <> '' then
      Fail(Doc, Node, 'the prefix "' + Esc(Prefix) + '" is not declared');
    NamespaceUri := '';
  end;
  { references inside a document without target namespace that was
    included into a namespace point into that namespace }
  if (NamespaceUri = '') and Doc.Chameleon then
    NamespaceUri := Doc.TargetNamespace;
  Result := LocalName <> '';
end;

function TLoader.QNameAttr(Doc: TSchemaDoc; Node: TLandrixXmlNode; const AttrName: TLandrixXmlUtf8;
  out NamespaceUri, LocalName: TLandrixXmlUtf8): Boolean;
var
  Value: TLandrixXmlUtf8;
begin
  NamespaceUri := '';
  LocalName := '';
  Result := Attr(Node, AttrName, Value);
  if Result and not ResolveQName(Doc, Node, Value, NamespaceUri, LocalName) then
    Fail(Doc, Node, 'empty name in "' + Esc(AttrName) + '"');
end;

{ Inside a redefinition its own name means the original component, as
  Xerces renames it, only where SelfOwner is the redefinition's node:
  the base of a redefined type, a group or attribute group reference
  anywhere in a redefined group. Everywhere else the name is the new
  component. }
function TLoader.FindPending(Kind: TPendingKind; const NamespaceUri,
  LocalName: TLandrixXmlUtf8; SelfOwner: TLandrixXmlNode): TPending;
var
  SameSpace: Boolean;
begin
  if (SelfOwner <> nil) and (FCurrent <> nil) and (FCurrent.Original <> nil) and (FCurrent.Node = SelfOwner) and
    (FCurrent.Name = LocalName) and (FCurrent.NamespaceUri = NamespaceUri) then
  begin
    SameSpace := (FCurrent.Kind = Kind) or
      ((FCurrent.Kind in [pkComplexType, pkSimpleType]) and (Kind in [pkComplexType, pkSimpleType]));
    if SameSpace then
    begin
      Result := FCurrent.Original;
      if Result.Kind <> Kind then
        Result := nil;
      Exit;
    end;
  end;
  Result := TPending(FMaps[Kind].Find(NamespaceUri, LocalName));
end;

function TLoader.MissingText(const What: string; const NamespaceUri, LocalName: TLandrixXmlUtf8): string;
var
  I: Integer;
begin
  Result := 'cannot find the ' + What + ' ' + QualifiedText(NamespaceUri, LocalName);
  for I := 0 to Integer(FSkippedImports.Count) - 1 do
    if Pos(Esc(NamespaceUri) + ' (', FSkippedImports[I]) = 1 then
    begin
      Result := Result + ' (the import of ' + FSkippedImports[I] +
        ' could not be resolved; add it to the resolver)';
      Break;
    end;
end;

function TLoader.LocalKey(Doc: TSchemaDoc; Node: TLandrixXmlNode): TLandrixXmlUtf8;
begin
  Result := PointerKey(Doc) + PointerKey(Node);
end;

{ --- elements ------------------------------------------------------------ }

function TLoader.ResolveElement(P: TPending): TLandrixXmlXsdElementDecl;
var
  Saved: TPending;
begin
  if P.Component <> nil then
  begin
    Result := TLandrixXmlXsdElementDecl(P.Component);
    Exit;
  end;
  Saved := FCurrent;
  FCurrent := P;
  try
    Result := BuildElement(P.Doc, P.Node, True, P);
  finally
    FCurrent := Saved;
  end;
end;

function TLoader.LocalElement(Doc: TSchemaDoc; Node: TLandrixXmlNode): TLandrixXmlXsdElementDecl;
var
  Key: TLandrixXmlUtf8;
begin
  Key := LocalKey(Doc, Node);
  Result := TLandrixXmlXsdElementDecl(FLocalCache.Find('', Key));
  if Result = nil then
    Result := BuildElement(Doc, Node, False, nil);
end;

function TLoader.BuildElement(Doc: TSchemaDoc; Node: TLandrixXmlNode; Global: Boolean;
  P: TPending): TLandrixXmlXsdElementDecl;
var
  D: TLandrixXmlXsdElementDecl;
  Name, Value, Form: TLandrixXmlUtf8;
  Child: TLandrixXmlNode;
  Simple: TLandrixXmlXsdSimpleType;
  Complex: TLandrixXmlXsdComplexType;
  TypePending: TPending;
  Qualified, HasDefault, HasFixed: Boolean;
  DefaultValue, FixedValue: TLandrixXmlUtf8;
begin
  if not AttrTrimmed(Node, 'name', Name) or (Name = '') then
    Fail(Doc, Node, 'an element declaration without a name');
  if Attr(Node, 'substitutionGroup', Value) then
    Unsupported(Doc, Node, 'substitution groups (element ' + Esc(Name) + ')');
  if BoolAttr(Node, 'abstract') then
    Unsupported(Doc, Node, 'abstract elements (element ' + Esc(Name) + ')');
  D := TLandrixXmlXsdElementDecl.Create;
  FSet.Own(D);
  D.Name := Name;
  D.Global := Global;
  D.SchemaFile := Doc.FileName;
  D.SchemaLine := Node.Line;
  if Global then
    D.NamespaceUri := Doc.TargetNamespace
  else
  begin
    if AttrTrimmed(Node, 'form', Form) then
      Qualified := Form = 'qualified'
    else
      Qualified := Doc.ElementQualified;
    if Qualified then
      D.NamespaceUri := Doc.TargetNamespace
    else
      D.NamespaceUri := '';
    FLocalCache.Add('', LocalKey(Doc, Node), D);
  end;
  if P <> nil then
  begin
    P.Component := D;
    P.State := psResolving;
    if FMaps[pkElement].Find(P.NamespaceUri, P.Name) = P then
      FSet.Elements.Put(D.NamespaceUri, D.Name, D);
  end;
  { the type }
  if Attr(Node, 'type', Value) then
  begin
    ResolveTypeRef(Doc, Node, 'type', Simple, Complex, TypePending);
    D.SimpleType := Simple;
    D.ComplexType := Complex;
  end;
  Child := Node.FirstChildElement;
  while Child <> nil do
  begin
    if IsXs(Child, 'complexType') or IsXs(Child, 'simpleType') then
    begin
      if (D.SimpleType <> nil) or (D.ComplexType <> nil) then
        Fail(Doc, Child, 'element ' + Esc(Name) + ' has both a type attribute and a local type');
      if IsXs(Child, 'complexType') then
        D.ComplexType := BuildComplexType(Doc, Child)
      else
        D.SimpleType := BuildSimpleType(Doc, Child, '', nil);
    end
    else if IsXs(Child, 'unique') or IsXs(Child, 'key') or IsXs(Child, 'keyref') then
      D.AddConstraint(BuildIdentity(Doc, Child))
    else if not IsXs(Child, 'annotation') then
      Fail(Doc, Child, 'unexpected element "' + Esc(Child.NameUtf8) + '" in element ' + Esc(Name));
    Child := Child.NextSiblingElement;
  end;
  if (D.SimpleType = nil) and (D.ComplexType = nil) then
    D.ComplexType := FSet.AnyType;
  HasDefault := Attr(Node, 'default', DefaultValue);
  HasFixed := Attr(Node, 'fixed', FixedValue);
  if HasDefault and HasFixed then
    Fail(Doc, Node, 'element ' + Esc(Name) + ' has both default and fixed');
  if HasDefault then
  begin
    D.ValueConstraint := xvcDefault;
    D.ConstraintValue := DefaultValue;
  end
  else if HasFixed then
  begin
    D.ValueConstraint := xvcFixed;
    D.ConstraintValue := FixedValue;
  end;
  if P <> nil then
    P.State := psDone;
  Result := D;
end;

{ --- attributes ---------------------------------------------------------- }

function TLoader.ResolveAttribute(P: TPending): TLandrixXmlXsdAttributeDecl;
var
  Saved: TPending;
begin
  if P.Component <> nil then
  begin
    Result := TLandrixXmlXsdAttributeDecl(P.Component);
    Exit;
  end;
  Saved := FCurrent;
  FCurrent := P;
  try
    Result := BuildAttribute(P.Doc, P.Node, True, P);
  finally
    FCurrent := Saved;
  end;
end;

function TLoader.BuildAttribute(Doc: TSchemaDoc; Node: TLandrixXmlNode; Global: Boolean;
  P: TPending): TLandrixXmlXsdAttributeDecl;
var
  D: TLandrixXmlXsdAttributeDecl;
  Name, Value, Form: TLandrixXmlUtf8;
  Child: TLandrixXmlNode;
  Simple: TLandrixXmlXsdSimpleType;
  Complex: TLandrixXmlXsdComplexType;
  TypePending: TPending;
  Qualified: Boolean;
begin
  if not AttrTrimmed(Node, 'name', Name) or (Name = '') then
    Fail(Doc, Node, 'an attribute declaration without a name');
  D := TLandrixXmlXsdAttributeDecl.Create;
  FSet.Own(D);
  D.Name := Name;
  D.Global := Global;
  D.SchemaFile := Doc.FileName;
  D.SchemaLine := Node.Line;
  if Global then
    D.NamespaceUri := Doc.TargetNamespace
  else
  begin
    if AttrTrimmed(Node, 'form', Form) then
      Qualified := Form = 'qualified'
    else
      Qualified := Doc.AttributeQualified;
    if Qualified then
      D.NamespaceUri := Doc.TargetNamespace
    else
      D.NamespaceUri := '';
  end;
  if P <> nil then
  begin
    P.Component := D;
    P.State := psResolving;
    if FMaps[pkAttribute].Find(P.NamespaceUri, P.Name) = P then
      FSet.Attributes.Put(D.NamespaceUri, D.Name, D);
  end;
  if Attr(Node, 'type', Value) then
  begin
    ResolveTypeRef(Doc, Node, 'type', Simple, Complex, TypePending);
    if Complex <> nil then
      Fail(Doc, Node, 'attribute ' + Esc(Name) + ' has a complex type');
    D.SimpleType := Simple;
  end;
  Child := Node.FirstChildElement;
  while Child <> nil do
  begin
    if IsXs(Child, 'simpleType') then
    begin
      if D.SimpleType <> nil then
        Fail(Doc, Child, 'attribute ' + Esc(Name) + ' has both a type attribute and a local type');
      D.SimpleType := BuildSimpleType(Doc, Child, '', nil);
    end
    else if not IsXs(Child, 'annotation') then
      Fail(Doc, Child, 'unexpected element "' + Esc(Child.NameUtf8) + '" in attribute ' + Esc(Name));
    Child := Child.NextSiblingElement;
  end;
  if D.SimpleType = nil then
    D.SimpleType := LandrixXmlXsdBuiltinType('anySimpleType');
  { the value constraint of a local declaration belongs to its use, as in
    Xerces (cvc-complex-type.3.1 rather than cvc-attribute.4) }
  if not Global then
  begin
    if P <> nil then
      P.State := psDone;
    Result := D;
    Exit;
  end;
  if Attr(Node, 'default', Value) then
  begin
    D.ValueConstraint := xvcDefault;
    D.ConstraintValue := Value;
  end;
  if Attr(Node, 'fixed', Value) then
  begin
    if D.ValueConstraint <> xvcNone then
      Fail(Doc, Node, 'attribute ' + Esc(Name) + ' has both default and fixed');
    D.ValueConstraint := xvcFixed;
    D.ConstraintValue := Value;
  end;
  if P <> nil then
    P.State := psDone;
  Result := D;
end;

{ --- types --------------------------------------------------------------- }

function TLoader.SimpleTypeRef(Doc: TSchemaDoc; Node: TLandrixXmlNode; const NamespaceUri,
  LocalName: TLandrixXmlUtf8; SelfOwner: TLandrixXmlNode): TLandrixXmlXsdSimpleType;
var
  P: TPending;
begin
  if NamespaceUri = LandrixXmlXsdNamespace then
  begin
    Result := LandrixXmlXsdBuiltinType(LocalName);
    if Result = nil then
    begin
      if LocalName = 'anyType' then
        Fail(Doc, Node, 'xs:anyType is not a simple type');
      Unsupported(Doc, Node, 'the type xs:' + Esc(LocalName));
    end;
    Exit;
  end;
  P := FindPending(pkSimpleType, NamespaceUri, LocalName, SelfOwner);
  if P = nil then
  begin
    if FindPending(pkComplexType, NamespaceUri, LocalName, SelfOwner) <> nil then
      Fail(Doc, Node, QualifiedText(NamespaceUri, LocalName) + ' is not a simple type');
    Fail(Doc, Node, MissingText('type', NamespaceUri, LocalName));
  end;
  Result := ResolveSimpleType(P);
end;

procedure TLoader.ResolveTypeRef(Doc: TSchemaDoc; Node: TLandrixXmlNode; const AttrName: TLandrixXmlUtf8;
  out Simple: TLandrixXmlXsdSimpleType; out Complex: TLandrixXmlXsdComplexType; out Pending: TPending);
var
  Ns, LocalName: TLandrixXmlUtf8;
begin
  Simple := nil;
  Complex := nil;
  Pending := nil;
  QNameAttr(Doc, Node, AttrName, Ns, LocalName);
  if (Ns = LandrixXmlXsdNamespace) and (LocalName = 'anyType') then
  begin
    Complex := FSet.AnyType;
    Exit;
  end;
  if Ns = LandrixXmlXsdNamespace then
  begin
    Simple := SimpleTypeRef(Doc, Node, Ns, LocalName);
    Exit;
  end;
  Pending := FindPending(pkComplexType, Ns, LocalName);
  if Pending <> nil then
  begin
    Complex := ResolveComplexType(Pending, False);
    Exit;
  end;
  Simple := SimpleTypeRef(Doc, Node, Ns, LocalName);
end;

function TLoader.ResolveSimpleType(P: TPending): TLandrixXmlXsdSimpleType;
var
  Saved: TPending;
begin
  if P.State = psResolving then
    Fail(P.Doc, P.Node, 'circular definition of the type ' + QualifiedText(P.NamespaceUri, P.Name));
  if P.Component <> nil then
  begin
    Result := TLandrixXmlXsdSimpleType(P.Component);
    Exit;
  end;
  Saved := FCurrent;
  FCurrent := P;
  try
    Result := BuildSimpleType(P.Doc, P.Node, P.Name, P);
  finally
    FCurrent := Saved;
  end;
end;

function TLoader.BuildSimpleType(Doc: TSchemaDoc; Node: TLandrixXmlNode; const Name: TLandrixXmlUtf8;
  P: TPending): TLandrixXmlXsdSimpleType;
var
  Child, Sub: TLandrixXmlNode;
  Base: TLandrixXmlXsdSimpleType;
  Members: TLandrixXmlXsdSimpleTypeArray;
  Ns, LocalName, Value, Item: TLandrixXmlUtf8;
  I, Start: Integer;
  Ns2: TLandrixXmlUtf8;
begin
  Result := nil;
  Members := nil;
  if P <> nil then
    P.State := psResolving;
  Child := Node.FirstChildElement;
  while IsXs(Child, 'annotation') do
    Child := Child.NextSiblingElement;
  if IsXs(Child, 'restriction') then
  begin
    Base := nil;
    if QNameAttr(Doc, Child, 'base', Ns, LocalName) then
      Base := SimpleTypeRef(Doc, Child, Ns, LocalName, Node);
    Sub := Child.FirstChildElement;
    while IsXs(Sub, 'annotation') do
      Sub := Sub.NextSiblingElement;
    if IsXs(Sub, 'simpleType') then
    begin
      if Base <> nil then
        Fail(Doc, Sub, 'a restriction with both a base attribute and a local simple type');
      Base := BuildSimpleType(Doc, Sub, '', nil);
    end;
    if Base = nil then
      Fail(Doc, Child, 'a restriction without a base type');
    if Name <> '' then
      Ns2 := Doc.TargetNamespace
    else
      Ns2 := '';
    Result := TLandrixXmlXsdSimpleType.CreateRestriction(Base, Ns2, Name);
    FSet.Own(Result);
    if Name = '' then
      Result.AnonymousName := AnonymousTypeName(Node);
    AddFacets(Doc, Child, Result);
  end
  else if IsXs(Child, 'union') then
  begin
    if Attr(Child, 'memberTypes', Value) then
    begin
      I := 1;
      while I <= Length(Value) do
      begin
        while (I <= Length(Value)) and IsSpace(AnsiChar(Value[I])) do
          Inc(I);
        Start := I;
        while (I <= Length(Value)) and not IsSpace(AnsiChar(Value[I])) do
          Inc(I);
        if I > Start then
        begin
          Item := Copy(Value, Start, I - Start);
          ResolveQName(Doc, Child, Item, Ns, LocalName);
          SetLength(Members, Length(Members) + 1);
          Members[High(Members)] := SimpleTypeRef(Doc, Child, Ns, LocalName);
        end;
      end;
    end;
    Sub := Child.FirstChildElement;
    while Sub <> nil do
    begin
      if IsXs(Sub, 'simpleType') then
      begin
        SetLength(Members, Length(Members) + 1);
        Members[High(Members)] := BuildSimpleType(Doc, Sub, '', nil);
      end
      else if not IsXs(Sub, 'annotation') then
        Fail(Doc, Sub, 'unexpected element "' + Esc(Sub.NameUtf8) + '" in xs:union');
      Sub := Sub.NextSiblingElement;
    end;
    if Length(Members) = 0 then
      Fail(Doc, Child, 'a union without member types');
    if Name <> '' then
      Ns2 := Doc.TargetNamespace
    else
      Ns2 := '';
    Result := TLandrixXmlXsdSimpleType.CreateUnion(Members, Ns2, Name);
    FSet.Own(Result);
    if Name = '' then
      Result.AnonymousName := AnonymousTypeName(Node);
  end
  else if IsXs(Child, 'list') then
    Unsupported(Doc, Child, 'xs:list')
  else
    Fail(Doc, Node, 'a simple type needs a restriction or a union');
  if P <> nil then
  begin
    P.Component := Result;
    P.State := psDone;
    if FMaps[pkSimpleType].Find(P.NamespaceUri, P.Name) = P then
      FSet.SimpleTypes.Put(P.NamespaceUri, P.Name, Result);
  end;
end;

procedure TLoader.AddFacets(Doc: TSchemaDoc; Restriction: TLandrixXmlNode; T: TLandrixXmlXsdSimpleType);
var
  Child: TLandrixXmlNode;
  LocalName, Value: TLandrixXmlUtf8;
  Facet: TLandrixXmlXsdFacet;
begin
  Child := Restriction.FirstChildElement;
  while Child <> nil do
  begin
    if IsXs(Child, 'annotation') or IsXs(Child, 'simpleType') then
    begin
      Child := Child.NextSiblingElement;
      Continue;
    end;
    if Child.NamespaceUriUtf8 <> LandrixXmlXsdNamespace then
      Fail(Doc, Child, 'unexpected element "' + Esc(Child.NameUtf8) + '" in a restriction');
    LocalName := Child.LocalNameUtf8;
    Facet := xsfLength;
    if LocalName = 'length' then Facet := xsfLength
    else if LocalName = 'minLength' then Facet := xsfMinLength
    else if LocalName = 'maxLength' then Facet := xsfMaxLength
    else if LocalName = 'pattern' then Facet := xsfPattern
    else if LocalName = 'enumeration' then Facet := xsfEnumeration
    else if LocalName = 'whiteSpace' then Facet := xsfWhiteSpace
    else if LocalName = 'maxInclusive' then Facet := xsfMaxInclusive
    else if LocalName = 'maxExclusive' then Facet := xsfMaxExclusive
    else if LocalName = 'minInclusive' then Facet := xsfMinInclusive
    else if LocalName = 'minExclusive' then Facet := xsfMinExclusive
    else if LocalName = 'totalDigits' then Facet := xsfTotalDigits
    else if LocalName = 'fractionDigits' then Facet := xsfFractionDigits
    else if (LocalName = 'attribute') or (LocalName = 'attributeGroup') or (LocalName = 'anyAttribute') then
    begin
      { attributes of a simple content restriction, handled by the caller }
      Child := Child.NextSiblingElement;
      Continue;
    end
    else
    begin
      Fail(Doc, Child, 'unexpected element "' + Esc(Child.NameUtf8) + '" in a restriction');
    end;
    if not Attr(Child, 'value', Value) then
      Fail(Doc, Child, 'facet ' + Esc(LocalName) + ' without a value');
    try
      T.AddFacet(Facet, Value);
    except
      on E: ELandrixXmlError do
      begin
        if E.Code = xecUnsupported then
          Unsupported(Doc, Child, E.Message)
        else
          Fail(Doc, Child, E.Message);
      end;
    end;
    Child := Child.NextSiblingElement;
  end;
end;

{ A named complex type. A reference (an element's type) only needs the
  object, which is filled later; a derivation needs the base complete. }
function TLoader.ResolveComplexType(P: TPending; NeedComplete: Boolean): TLandrixXmlXsdComplexType;
var
  Saved: TPending;
begin
  if P.Component = nil then
    CreateComplexType(P.Doc, P.Node, P.Name, P);
  Result := TLandrixXmlXsdComplexType(P.Component);
  if not NeedComplete or (P.State = psDone) then
    Exit;
  if P.State = psResolving then
    Fail(P.Doc, P.Node, 'circular derivation of the type ' + QualifiedText(P.NamespaceUri, P.Name));
  Saved := FCurrent;
  FCurrent := P;
  try
    FillComplexType(Result, P.Doc, P.Node, P);
  finally
    FCurrent := Saved;
  end;
end;

{ An anonymous complex type, complete. }
function TLoader.BuildComplexType(Doc: TSchemaDoc; Node: TLandrixXmlNode): TLandrixXmlXsdComplexType;
begin
  Result := CreateComplexType(Doc, Node, '', nil);
  FillComplexType(Result, Doc, Node, nil);
end;

function TLoader.WildcardFor(Doc: TSchemaDoc; Node: TLandrixXmlNode): TLandrixXmlXsdWildcard;
var
  Key, Value, Item: TLandrixXmlUtf8;
  Namespaces: TLandrixXmlUtf8Array;
  Constraint: TLandrixXmlXsdNamespaceConstraint;
  I, Start: Integer;
begin
  Key := LocalKey(Doc, Node);
  Result := TLandrixXmlXsdWildcard(FLocalCache.Find('', Key));
  if Result <> nil then
    Exit;
  Namespaces := nil;
  Constraint := xncAny;
  if AttrTrimmed(Node, 'namespace', Value) and (Value <> '##any') then
  begin
    if Value = '##other' then
    begin
      Constraint := xncNot;
      SetLength(Namespaces, 1);
      Namespaces[0] := Doc.TargetNamespace;
    end
    else
    begin
      Constraint := xncList;
      I := 1;
      while I <= Length(Value) do
      begin
        while (I <= Length(Value)) and IsSpace(AnsiChar(Value[I])) do
          Inc(I);
        Start := I;
        while (I <= Length(Value)) and not IsSpace(AnsiChar(Value[I])) do
          Inc(I);
        if I > Start then
        begin
          Item := Copy(Value, Start, I - Start);
          if Item = '##targetNamespace' then
            Item := Doc.TargetNamespace
          else if Item = '##local' then
            Item := '';
          SetLength(Namespaces, Length(Namespaces) + 1);
          Namespaces[High(Namespaces)] := Item;
        end;
      end;
    end;
  end;
  Result := TLandrixXmlXsdWildcard.Create;
  FSet.Own(Result);
  Result.SetNamespaces(Constraint, Namespaces);
  Result.SchemaFile := Doc.FileName;
  Result.SchemaLine := Node.Line;
  Result.ProcessContents := xpcStrict;
  if AttrTrimmed(Node, 'processContents', Value) then
  begin
    if Value = 'lax' then
      Result.ProcessContents := xpcLax
    else if Value = 'skip' then
      Result.ProcessContents := xpcSkip
    else if Value <> 'strict' then
      Fail(Doc, Node, 'invalid processContents "' + Esc(Value) + '"');
  end;
  FLocalCache.Add('', Key, Result);
end;

function InSet(const S: TLandrixXmlUtf8; const List: TLandrixXmlUtf8Array): Boolean;
var
  I: Integer;
begin
  for I := 0 to Integer(Length(List)) - 1 do
    if List[I] = S then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

function SameWildcard(A, B: TLandrixXmlXsdWildcard): Boolean;
var
  I: Integer;
begin
  Result := A.Constraint = B.Constraint;
  if not Result then
    Exit;
  case A.Constraint of
    xncNot:
      Result := A.Namespaces[0] = B.Namespaces[0];
    xncList:
      begin
        Result := Length(A.Namespaces) = Length(B.Namespaces);
        if Result then
          for I := 0 to Integer(Length(A.Namespaces)) - 1 do
            if not InSet(A.Namespaces[I], B.Namespaces) then
              Result := False;
      end;
  else
    { any }
  end;
end;

{ The union (for an extension) or intersection (for attribute groups and
  the own wildcard) of two attribute wildcards, as Xerces forms them; the
  result has the process contents of A. A missing namespace is '' (a
  "not" wildcard excludes it as well). }
function TLoader.CombineWildcards(A, B: TLandrixXmlXsdWildcard; Union: Boolean; Doc: TSchemaDoc;
  Node: TLandrixXmlNode): TLandrixXmlXsdWildcard;
var
  C: TLandrixXmlXsdNamespaceConstraint;
  L, List: TLandrixXmlUtf8Array;
  Other: TLandrixXmlUtf8;
  I: Integer;
  FoundNs, FoundAbsent, Expressible: Boolean;
begin
  L := nil;
  List := nil;
  Expressible := True;
  C := xncAny;
  if SameWildcard(A, B) then
  begin
    C := A.Constraint;
    L := A.Namespaces;
  end
  else if Union then
  begin
    if (A.Constraint = xncAny) or (B.Constraint = xncAny) then
      C := xncAny
    else if (A.Constraint = xncList) and (B.Constraint = xncList) then
    begin
      C := xncList;
      L := Copy(A.Namespaces, 0, Length(A.Namespaces));
      for I := 0 to Integer(Length(B.Namespaces)) - 1 do
        if not InSet(B.Namespaces[I], L) then
        begin
          SetLength(L, Length(L) + 1);
          L[High(L)] := B.Namespaces[I];
        end;
    end
    else if (A.Constraint = xncNot) and (B.Constraint = xncNot) then
    begin
      C := xncNot;
      SetLength(L, 1);
      L[0] := '';
    end
    else
    begin
      if A.Constraint = xncNot then
      begin
        Other := A.Namespaces[0];
        List := B.Namespaces;
      end
      else
      begin
        Other := B.Namespaces[0];
        List := A.Namespaces;
      end;
      FoundAbsent := InSet('', List);
      FoundNs := (Other <> '') and InSet(Other, List);
      C := xncNot;
      SetLength(L, 1);
      L[0] := Other;
      if Other = '' then
      begin
        if FoundAbsent then
          C := xncAny;
      end
      else if FoundNs and FoundAbsent then
        C := xncAny
      else if FoundNs then
        L[0] := ''
      else if FoundAbsent then
        Expressible := False;
    end;
  end
  else
  begin
    if A.Constraint = xncAny then
    begin
      C := B.Constraint;
      L := B.Namespaces;
    end
    else if B.Constraint = xncAny then
    begin
      C := A.Constraint;
      L := A.Namespaces;
    end
    else if (A.Constraint = xncNot) and (B.Constraint = xncNot) then
    begin
      if (A.Namespaces[0] <> '') and (B.Namespaces[0] <> '') then
        Expressible := False
      else if A.Namespaces[0] = '' then
      begin
        C := B.Constraint;
        L := B.Namespaces;
      end
      else
      begin
        C := A.Constraint;
        L := A.Namespaces;
      end;
    end
    else
    begin
      C := xncList;
      if A.Constraint = xncList then
        List := A.Namespaces
      else
        List := B.Namespaces;
      for I := 0 to Integer(Length(List)) - 1 do
        if ((A.Constraint = xncList) and (B.Constraint = xncList) and InSet(List[I], B.Namespaces)) or
          ((A.Constraint = xncNot) and (List[I] <> A.Namespaces[0]) and (List[I] <> '')) or
          ((B.Constraint = xncNot) and (List[I] <> B.Namespaces[0]) and (List[I] <> '')) then
        begin
          SetLength(L, Length(L) + 1);
          L[High(L)] := List[I];
        end;
    end;
  end;
  if not Expressible then
    Fail(Doc, Node, 'the attribute wildcards cannot be combined');
  if C = xncAny then
    L := nil;
  Result := TLandrixXmlXsdWildcard.Create;
  FSet.Own(Result);
  Result.SetNamespaces(C, L);
  Result.SchemaFile := A.SchemaFile;
  Result.SchemaLine := A.SchemaLine;
  Result.ProcessContents := A.ProcessContents;
end;

procedure ParseOccurs(Loader: TLoader; Doc: TSchemaDoc; Node: TLandrixXmlNode;
  out MinOccurs, MaxOccurs: Integer);
var
  Value: TLandrixXmlUtf8;
begin
  MinOccurs := 1;
  MaxOccurs := 1;
  if AttrTrimmed(Node, 'minOccurs', Value) then
    MinOccurs := StrToIntDef(LandrixXmlUtf8ToString(Value), -1);
  if AttrTrimmed(Node, 'maxOccurs', Value) then
  begin
    if Value = 'unbounded' then
      MaxOccurs := LandrixXmlXsdUnbounded
    else
      MaxOccurs := StrToIntDef(LandrixXmlUtf8ToString(Value), -2);
  end;
  if (MinOccurs < 0) or (MaxOccurs < -1) or ((MaxOccurs >= 0) and (MaxOccurs < MinOccurs)) then
    Loader.Fail(Doc, Node, 'invalid minOccurs or maxOccurs');
end;

function TLoader.BuildCompositor(Doc: TSchemaDoc; Node: TLandrixXmlNode; MinOccurs,
  MaxOccurs: Integer): TLandrixXmlXsdParticle;
var
  Child: TLandrixXmlNode;
  Sub: TLandrixXmlXsdParticle;
begin
  if IsXs(Node, 'all') then
    Unsupported(Doc, Node, 'xs:all');
  if IsXs(Node, 'sequence') then
    Result := TLandrixXmlXsdParticle.CreateGroup(xpkSequence, MinOccurs, MaxOccurs)
  else if IsXs(Node, 'choice') then
    Result := TLandrixXmlXsdParticle.CreateGroup(xpkChoice, MinOccurs, MaxOccurs)
  else
  begin
    Fail(Doc, Node, 'a sequence or choice was expected');
    Result := nil;
  end;
  try
    Child := Node.FirstChildElement;
    while Child <> nil do
    begin
      if not IsXs(Child, 'annotation') then
      begin
        Sub := BuildParticle(Doc, Child);
        if Sub <> nil then
          Result.Add(Sub);
      end;
      Child := Child.NextSiblingElement;
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ A particle as written: nil for maxOccurs="0" (Xerces drops it). }
function TLoader.BuildParticle(Doc: TSchemaDoc; Node: TLandrixXmlNode): TLandrixXmlXsdParticle;
var
  MinOccurs, MaxOccurs: Integer;
  Ns, LocalName: TLandrixXmlUtf8;
  P, Saved: TPending;
  D: TLandrixXmlXsdElementDecl;
  W: TLandrixXmlXsdWildcard;
  Inner: TLandrixXmlNode;
begin
  Result := nil;
  ParseOccurs(Self, Doc, Node, MinOccurs, MaxOccurs);
  if IsXs(Node, 'element') then
  begin
    if QNameAttr(Doc, Node, 'ref', Ns, LocalName) then
    begin
      P := FindPending(pkElement, Ns, LocalName);
      if P = nil then
        Fail(Doc, Node, MissingText('element', Ns, LocalName));
      D := ResolveElement(P);
    end
    else
      D := LocalElement(Doc, Node);
    if MaxOccurs = 0 then
      Exit;
    Result := TLandrixXmlXsdParticle.CreateElement(D.NamespaceUri, D.Name, D, MinOccurs, MaxOccurs);
  end
  else if IsXs(Node, 'any') then
  begin
    W := WildcardFor(Doc, Node);
    if MaxOccurs = 0 then
      Exit;
    Result := TLandrixXmlXsdParticle.CreateWildcard(W.Constraint, W.Namespaces, W, MinOccurs, MaxOccurs);
  end
  else if IsXs(Node, 'group') then
  begin
    if not QNameAttr(Doc, Node, 'ref', Ns, LocalName) then
      Fail(Doc, Node, 'a group reference without ref');
    if FCurrent <> nil then
      P := FindPending(pkGroup, Ns, LocalName, FCurrent.Node)
    else
      P := FindPending(pkGroup, Ns, LocalName);
    if P = nil then
      Fail(Doc, Node, MissingText('group', Ns, LocalName));
    if P.State = psResolving then
      Fail(Doc, Node, 'circular group reference ' + QualifiedText(Ns, LocalName));
    Inner := P.Node.FirstChildElement;
    while IsXs(Inner, 'annotation') do
      Inner := Inner.NextSiblingElement;
    if Inner = nil then
      Fail(P.Doc, P.Node, 'an empty group definition');
    Saved := FCurrent;
    FCurrent := P;
    P.State := psResolving;
    try
      Result := BuildCompositor(P.Doc, Inner, MinOccurs, MaxOccurs);
    finally
      P.State := psDone;
      FCurrent := Saved;
    end;
    if MaxOccurs = 0 then
    begin
      Result.Free;
      Result := nil;
    end;
  end
  else if IsXs(Node, 'sequence') or IsXs(Node, 'choice') or IsXs(Node, 'all') then
  begin
    Result := BuildCompositor(Doc, Node, MinOccurs, MaxOccurs);
    if MaxOccurs = 0 then
    begin
      Result.Free;
      Result := nil;
    end;
  end
  else
    Fail(Doc, Node, 'unexpected element "' + Esc(Node.NameUtf8) + '" in a model group');
end;

{ The particle of a type definition's model group child, nil if none. }
function TLoader.ParticleOfChildren(Doc: TSchemaDoc; Parent: TLandrixXmlNode): TLandrixXmlXsdParticle;
var
  Child: TLandrixXmlNode;
begin
  Result := nil;
  Child := Parent.FirstChildElement;
  while Child <> nil do
  begin
    if IsXs(Child, 'group') or IsXs(Child, 'sequence') or IsXs(Child, 'choice') or IsXs(Child, 'all') then
    begin
      Result := BuildParticle(Doc, Child);
      Exit;
    end;
    Child := Child.NextSiblingElement;
  end;
end;

{ Xerces makes the content empty only for a sequence or all (or a choice
  with minOccurs 0) directly below Parent that has no children except
  annotations; other particles that admit nothing give element-only
  content with a model that rejects every child. }
function IsEmptyCompositor(Parent: TLandrixXmlNode): Boolean;
var
  Child, Sub: TLandrixXmlNode;
  Value: TLandrixXmlUtf8;
begin
  Result := False;
  Child := Parent.FirstChildElement;
  while IsXs(Child, 'annotation') do
    Child := Child.NextSiblingElement;
  if (Child = nil) or not (IsXs(Child, 'sequence') or IsXs(Child, 'all') or
    (IsXs(Child, 'choice') and AttrTrimmed(Child, 'minOccurs', Value) and (Value = '0'))) then
    Exit;
  Sub := Child.FirstChildElement;
  while IsXs(Sub, 'annotation') do
    Sub := Sub.NextSiblingElement;
  Result := Sub = nil;
end;

{ The content particle of a complex type, built afresh (also the base
  type's for an extension), nil for empty content. }
function TLoader.EffectiveParticle(Doc: TSchemaDoc; TypeNode: TLandrixXmlNode): TLandrixXmlXsdParticle;
var
  Child, Derivation: TLandrixXmlNode;
  Own, BaseParticle: TLandrixXmlXsdParticle;
  Ns, LocalName: TLandrixXmlUtf8;
  BasePending, Saved: TPending;
begin
  Result := nil;
  Child := TypeNode.FirstChildElement;
  while IsXs(Child, 'annotation') do
    Child := Child.NextSiblingElement;
  if IsXs(Child, 'simpleContent') then
    Exit;
  if not IsXs(Child, 'complexContent') then
  begin
    Result := ParticleOfChildren(Doc, TypeNode);
    if (Result <> nil) and IsEmptyCompositor(TypeNode) then
    begin
      Result.Free;
      Result := nil;
    end;
    Exit;
  end;
  Derivation := Child.FirstChildElement;
  while IsXs(Derivation, 'annotation') do
    Derivation := Derivation.NextSiblingElement;
  { the base first: these raise for a bad name before Own exists }
  BasePending := nil;
  if not IsXs(Derivation, 'restriction') then
  begin
    QNameAttr(Doc, Derivation, 'base', Ns, LocalName);
    BasePending := FindPending(pkComplexType, Ns, LocalName, TypeNode);
  end;
  Own := ParticleOfChildren(Doc, Derivation);
  if (Own <> nil) and IsEmptyCompositor(Derivation) then
  begin
    Own.Free;
    Own := nil;
  end;
  if IsXs(Derivation, 'restriction') then
  begin
    Result := Own;
    Exit;
  end;
  { extension: the base type's content, then the own one }
  BaseParticle := nil;
  if BasePending <> nil then
  begin
    Saved := FCurrent;
    FCurrent := BasePending;
    try
      try
        BaseParticle := EffectiveParticle(BasePending.Doc, BasePending.Node);
      except
        Own.Free;
        raise;
      end;
    finally
      FCurrent := Saved;
    end;
  end;
  if BaseParticle = nil then
    Result := Own
  else if Own = nil then
    Result := BaseParticle
  else
  begin
    Result := TLandrixXmlXsdParticle.CreateGroup(xpkSequence, 1, 1);
    Result.Add(BaseParticle);
    Result.Add(Own);
  end;
end;

{ Attribute uses, prohibitions and the wildcard below Parent, attribute
  groups expanded. }
procedure TLoader.CollectAttributes(Doc: TSchemaDoc; Parent: TLandrixXmlNode; Items: TObjectList;
  var Wildcard: TLandrixXmlXsdWildcard);
var
  Child: TLandrixXmlNode;
  Item: TAttributeItem;
  Ns, LocalName, Value: TLandrixXmlUtf8;
  P, Saved: TPending;
  W, GroupWildcard: TLandrixXmlXsdWildcard;
  I: Integer;
begin
  Child := Parent.FirstChildElement;
  while Child <> nil do
  begin
    if IsXs(Child, 'attribute') then
    begin
      Item := TAttributeItem.Create;
      Items.Add(Item);
      if QNameAttr(Doc, Child, 'ref', Ns, LocalName) then
      begin
        P := FindPending(pkAttribute, Ns, LocalName);
        if P = nil then
        begin
          if Ns = LandrixXmlNamespaceXml then
            Fail(Doc, Child, MissingText('attribute', Ns, LocalName) +
              ' (import xml.xsd for the xml: attributes)')
          else
            Fail(Doc, Child, MissingText('attribute', Ns, LocalName));
        end;
        Item.Decl := ResolveAttribute(P);
        if Attr(Child, 'default', Value) then
        begin
          Item.ValueConstraint := xvcDefault;
          Item.ConstraintValue := Value;
        end;
        if Attr(Child, 'fixed', Value) then
        begin
          Item.ValueConstraint := xvcFixed;
          Item.ConstraintValue := Value;
        end;
      end
      else
      begin
        Item.Decl := TLandrixXmlXsdAttributeDecl(FLocalCache.Find('', LocalKey(Doc, Child)));
        if Item.Decl = nil then
        begin
          Item.Decl := BuildAttribute(Doc, Child, False, nil);
          FLocalCache.Add('', LocalKey(Doc, Child), Item.Decl);
        end;
        if Attr(Child, 'default', Value) then
        begin
          Item.ValueConstraint := xvcDefault;
          Item.ConstraintValue := Value;
        end;
        if Attr(Child, 'fixed', Value) then
        begin
          if Item.ValueConstraint <> xvcNone then
            Fail(Doc, Child, 'attribute ' + Esc(Item.Decl.Name) + ' has both default and fixed');
          Item.ValueConstraint := xvcFixed;
          Item.ConstraintValue := Value;
        end;
      end;
      if AttrTrimmed(Child, 'use', Value) then
      begin
        if Value = 'required' then
          Item.Required := True
        else if Value = 'prohibited' then
          Item.Prohibited := True
        else if Value <> 'optional' then
          Fail(Doc, Child, 'invalid use "' + Esc(Value) + '"');
      end;
      for I := 0 to Integer(Items.Count) - 2 do
        if (TAttributeItem(Items[I]).Decl.Name = Item.Decl.Name) and
          (TAttributeItem(Items[I]).Decl.NamespaceUri = Item.Decl.NamespaceUri) then
          Fail(Doc, Child, 'duplicate attribute ' + QualifiedText(Item.Decl.NamespaceUri, Item.Decl.Name));
    end
    else if IsXs(Child, 'attributeGroup') then
    begin
      if not QNameAttr(Doc, Child, 'ref', Ns, LocalName) then
        Fail(Doc, Child, 'an attribute group reference without ref');
      if FCurrent <> nil then
        P := FindPending(pkAttributeGroup, Ns, LocalName, FCurrent.Node)
      else
        P := FindPending(pkAttributeGroup, Ns, LocalName);
      if P = nil then
        Fail(Doc, Child, MissingText('attribute group', Ns, LocalName));
      if P.State = psResolving then
        Fail(Doc, Child, 'circular attribute group reference ' + QualifiedText(Ns, LocalName));
      Saved := FCurrent;
      FCurrent := P;
      P.State := psResolving;
      GroupWildcard := nil;
      try
        CollectAttributes(P.Doc, P.Node, Items, GroupWildcard);
      finally
        P.State := psDone;
        FCurrent := Saved;
      end;
      { the wildcards of the groups and the own one are intersected }
      if Wildcard = nil then
        Wildcard := GroupWildcard
      else if GroupWildcard <> nil then
        Wildcard := CombineWildcards(Wildcard, GroupWildcard, False, Doc, Child);
    end
    else if IsXs(Child, 'anyAttribute') then
    begin
      W := WildcardFor(Doc, Child);
      if Wildcard = nil then
        Wildcard := W
      else
        Wildcard := CombineWildcards(W, Wildcard, False, Doc, Child);
    end;
    Child := Child.NextSiblingElement;
  end;
end;

function TLoader.CreateComplexType(Doc: TSchemaDoc; Node: TLandrixXmlNode; const Name: TLandrixXmlUtf8;
  P: TPending): TLandrixXmlXsdComplexType;
var
  T: TLandrixXmlXsdComplexType;
begin
  T := TLandrixXmlXsdComplexType.Create;
  FSet.Own(T);
  T.Name := Name;
  if Name <> '' then
  begin
    T.NamespaceUri := Doc.TargetNamespace;
    T.DisplayName := Name;
  end
  else
    T.DisplayName := AnonymousTypeName(Node);
  T.SchemaFile := Doc.FileName;
  T.SchemaLine := Node.Line;
  T.Abstract := BoolAttr(Node, 'abstract');
  if P <> nil then
  begin
    P.Component := T;
    if FMaps[pkComplexType].Find(P.NamespaceUri, P.Name) = P then
      FSet.ComplexTypes.Put(P.NamespaceUri, P.Name, T);
  end;
  Result := T;
end;

{ True if the particle admits no children at all, as Xerces' isEmptiable. }
function Emptiable(P: TLandrixXmlXsdParticle): Boolean;
var
  I: Integer;
begin
  Result := True;
  if (P = nil) or (P.MinOccurs = 0) then
    Exit;
  case P.Kind of
    xpkSequence:
      for I := 0 to P.ChildCount - 1 do
        if not Emptiable(P.Children[I]) then
        begin
          Result := False;
          Exit;
        end;
    xpkChoice:
      begin
        Result := P.ChildCount = 0;
        for I := 0 to P.ChildCount - 1 do
          if Emptiable(P.Children[I]) then
            Result := True;
      end;
  else
    Result := False;
  end;
end;

function HasLocalSimpleType(Derivation: TLandrixXmlNode): Boolean;
var
  Sub: TLandrixXmlNode;
begin
  Sub := Derivation.FirstChildElement;
  while IsXs(Sub, 'annotation') do
    Sub := Sub.NextSiblingElement;
  Result := IsXs(Sub, 'simpleType');
end;

procedure TLoader.FillComplexType(T: TLandrixXmlXsdComplexType; Doc: TSchemaDoc; Node: TLandrixXmlNode;
  P: TPending);
var
  BaseType: TLandrixXmlXsdComplexType;
  Child, Derivation, Sub: TLandrixXmlNode;
  Mixed, IsExtension, IsSimpleContent: Boolean;
  Ns, LocalName, Value: TLandrixXmlUtf8;
  BasePending: TPending;
  BaseSimple, Simple: TLandrixXmlXsdSimpleType;
  Items: TObjectList;
  Wildcard: TLandrixXmlXsdWildcard;
  Particle: TLandrixXmlXsdParticle;
  I, J: Integer;
  Item: TAttributeItem;
  Use: TLandrixXmlXsdAttributeUse;
  Found, HasFacets: Boolean;
begin
  if P <> nil then
    P.State := psResolving;
  Mixed := BoolAttr(Node, 'mixed');
  Child := Node.FirstChildElement;
  while IsXs(Child, 'annotation') do
    Child := Child.NextSiblingElement;
  IsSimpleContent := IsXs(Child, 'simpleContent');
  BaseType := FSet.AnyType;
  BaseSimple := nil;
  IsExtension := False;
  Derivation := Node;
  if IsSimpleContent or IsXs(Child, 'complexContent') then
  begin
    if IsXs(Child, 'complexContent') and Attr(Child, 'mixed', Value) then
      Mixed := BoolAttr(Child, 'mixed');
    Derivation := Child.FirstChildElement;
    while IsXs(Derivation, 'annotation') do
      Derivation := Derivation.NextSiblingElement;
    if IsXs(Derivation, 'extension') then
      IsExtension := True
    else if not IsXs(Derivation, 'restriction') then
      Fail(Doc, Child, 'an extension or restriction was expected');
    if not QNameAttr(Doc, Derivation, 'base', Ns, LocalName) then
      Fail(Doc, Derivation, 'a derivation without a base type');
    BaseType := nil;
    if (Ns = LandrixXmlXsdNamespace) and (LocalName = 'anyType') then
      BaseType := FSet.AnyType
    else
    begin
      BasePending := FindPending(pkComplexType, Ns, LocalName, Node);
      if BasePending <> nil then
        BaseType := ResolveComplexType(BasePending, True)
      else if IsSimpleContent then
        BaseSimple := SimpleTypeRef(Doc, Derivation, Ns, LocalName, Node)
      else
        Fail(Doc, Derivation, MissingText('complex type', Ns, LocalName));
    end;
    if (BaseType = FSet.AnyType) and IsExtension and not IsSimpleContent then
      Unsupported(Doc, Derivation, 'extending xs:anyType');
  end;
  T.BaseComplex := BaseType;
  T.BaseSimple := BaseSimple;
  if IsExtension then
    T.Derivation := xdExtension
  else
    T.Derivation := xdRestriction;
  { content }
  if IsSimpleContent then
  begin
    T.ContentType := xctSimple;
    Simple := nil;
    if BaseSimple <> nil then
      Simple := BaseSimple
    else if (BaseType <> nil) and (BaseType.ContentType = xctSimple) then
      Simple := BaseType.SimpleType
    else if (BaseType = nil) or IsExtension or (BaseType.ContentType <> xctMixed) or
      ((BaseType.Model <> nil) and not Emptiable(BaseType.Model.Root)) or not HasLocalSimpleType(Derivation) then
      { a mixed base with emptiable content may be restricted to the local
        simple type of the restriction }
      Fail(Doc, Derivation, 'the base of simple content must have simple content');
    if not IsExtension then
    begin
      { a restriction of simple content: an anonymous restriction of the
        base's simple type (or of a local one) with the facets }
      Sub := Derivation.FirstChildElement;
      while IsXs(Sub, 'annotation') do
        Sub := Sub.NextSiblingElement;
      if IsXs(Sub, 'simpleType') then
        Simple := BuildSimpleType(Doc, Sub, '', nil);
      HasFacets := False;
      Sub := Derivation.FirstChildElement;
      while Sub <> nil do
      begin
        if not (IsXs(Sub, 'annotation') or IsXs(Sub, 'simpleType') or IsXs(Sub, 'attribute') or
          IsXs(Sub, 'attributeGroup') or IsXs(Sub, 'anyAttribute')) then
          HasFacets := True;
        Sub := Sub.NextSiblingElement;
      end;
      if HasFacets then
      begin
        Simple := TLandrixXmlXsdSimpleType.CreateRestriction(Simple, '', '');
        FSet.Own(Simple);
        Simple.AnonymousName := AnonymousTypeName(Child);
        AddFacets(Doc, Derivation, Simple);
      end;
    end;
    T.SimpleType := Simple;
  end
  else
  begin
    Particle := EffectiveParticle(Doc, Node);
    if Particle = nil then
    begin
      if IsExtension and (BaseType <> nil) and (BaseType.ContentType in [xctSimple]) then
        Fail(Doc, Derivation, 'complex content cannot extend simple content');
      if Mixed then
      begin
        { text only: an empty model rejects every child (2.4.d) }
        T.ContentType := xctMixed;
        T.Model := TLandrixXmlXsdContentModel.Create(nil);
      end
      else
        T.ContentType := xctEmpty;
    end
    else
    begin
      if Mixed then
        T.ContentType := xctMixed
      else if IsExtension and (BaseType <> nil) and (BaseType.ContentType = xctMixed) then
        T.ContentType := xctMixed
      else
        T.ContentType := xctElementOnly;
      if Particle.IsLeaf then
      begin
        { cannot happen: a type's particle is a model group }
        Particle.Free;
        Fail(Doc, Node, 'a content model must be a model group');
      end;
      T.Model := TLandrixXmlXsdContentModel.Create(Particle);
    end;
  end;
  { attributes }
  Items := TObjectList.Create(True);
  try
    Wildcard := nil;
    CollectAttributes(Doc, Derivation, Items, Wildcard);
    if (BaseType <> nil) and (BaseType <> FSet.AnyType) then
    begin
      if IsExtension then
      begin
        for I := 0 to BaseType.AttributeCount - 1 do
        begin
          Use := TLandrixXmlXsdAttributeUse.Create;
          Use.Decl := BaseType.Attributes[I].Decl;
          Use.Required := BaseType.Attributes[I].Required;
          Use.ValueConstraint := BaseType.Attributes[I].ValueConstraint;
          Use.ConstraintValue := BaseType.Attributes[I].ConstraintValue;
          T.AddAttribute(Use);
        end;
        { an extension has the union of the wildcards }
        if Wildcard = nil then
          Wildcard := BaseType.AttributeWildcard
        else if BaseType.AttributeWildcard <> nil then
          Wildcard := CombineWildcards(Wildcard, BaseType.AttributeWildcard, True, Doc, Derivation);
      end
      else
      begin
        { a restriction keeps the base's attributes it does not change }
        for I := 0 to BaseType.AttributeCount - 1 do
        begin
          Found := False;
          for J := 0 to Integer(Items.Count) - 1 do
          begin
            Item := TAttributeItem(Items[J]);
            if (Item.Decl.Name = BaseType.Attributes[I].Decl.Name) and
              (Item.Decl.NamespaceUri = BaseType.Attributes[I].Decl.NamespaceUri) then
              Found := True;
          end;
          if not Found then
          begin
            Use := TLandrixXmlXsdAttributeUse.Create;
            Use.Decl := BaseType.Attributes[I].Decl;
            Use.Required := BaseType.Attributes[I].Required;
            Use.ValueConstraint := BaseType.Attributes[I].ValueConstraint;
            Use.ConstraintValue := BaseType.Attributes[I].ConstraintValue;
            T.AddAttribute(Use);
          end;
        end;
      end;
    end;
    for I := 0 to Integer(Items.Count) - 1 do
    begin
      Item := TAttributeItem(Items[I]);
      if Item.Prohibited then
        Continue;
      if IsExtension and (T.FindAttribute(Item.Decl.NamespaceUri, Item.Decl.Name) <> nil) then
        Fail(Doc, Derivation, 'the extension redeclares the attribute ' +
          QualifiedText(Item.Decl.NamespaceUri, Item.Decl.Name));
      Use := TLandrixXmlXsdAttributeUse.Create;
      Use.Decl := Item.Decl;
      Use.Required := Item.Required;
      Use.ValueConstraint := Item.ValueConstraint;
      Use.ConstraintValue := Item.ConstraintValue;
      T.AddAttribute(Use);
    end;
    T.AttributeWildcard := Wildcard;
  finally
    Items.Free;
  end;
  if P <> nil then
    P.State := psDone;
end;

{ --- identity constraints ------------------------------------------------- }

function TLoader.ParsePaths(Doc: TSchemaDoc; Node: TLandrixXmlNode; const Expr: TLandrixXmlUtf8;
  IsField: Boolean): TLandrixXmlXsdPaths;
var
  Parts: TLandrixXmlUtf8Array;
  I, J, K, N, Start: Integer;
  Part, StepText, Prefix: TLandrixXmlUtf8;
  Path: TLandrixXmlXsdPath;
  Step: TLandrixXmlXsdPathStep;
  Steps: TLandrixXmlUtf8Array;

  procedure Bad;
  begin
    Unsupported(Doc, Node, 'the XPath expression "' + Esc(Expr) + '"');
  end;

begin
  Result := nil;
  Parts := nil;
  { split at '|' }
  Start := 1;
  for I := 1 to Length(Expr) + 1 do
    if (I > Length(Expr)) or (Expr[I] = '|') then
    begin
      SetLength(Parts, Length(Parts) + 1);
      Parts[High(Parts)] := Trimmed(Copy(Expr, Start, I - Start));
      Start := I + 1;
    end;
  for I := 0 to Integer(Length(Parts)) - 1 do
  begin
    Part := Parts[I];
    Path.Descendant := False;
    Path.Steps := nil;
    if Copy(Part, 1, 3) = './/' then
    begin
      Path.Descendant := True;
      Part := Trimmed(Copy(Part, 4, MaxInt));
    end;
    if Part = '' then
      Bad;
    { split at '/' }
    Steps := nil;
    Start := 1;
    for J := 1 to Length(Part) + 1 do
      if (J > Length(Part)) or (Part[J] = '/') then
      begin
        SetLength(Steps, Length(Steps) + 1);
        Steps[High(Steps)] := Trimmed(Copy(Part, Start, J - Start));
        Start := J + 1;
      end;
    for J := 0 to Integer(Length(Steps)) - 1 do
    begin
      StepText := Steps[J];
      if StepText = '' then
        Bad;
      if StepText = '.' then
        Continue;
      Step.AnyName := False;
      Step.AnyLocalName := False;
      Step.NamespaceUri := '';
      Step.LocalName := '';
      Step.IsAttribute := False;
      if StepText[1] = '@' then
      begin
        Step.IsAttribute := True;
        StepText := Trimmed(Copy(StepText, 2, MaxInt));
      end
      else if Copy(StepText, 1, 11) = 'attribute::' then
      begin
        Step.IsAttribute := True;
        StepText := Trimmed(Copy(StepText, 12, MaxInt));
      end
      else if Copy(StepText, 1, 7) = 'child::' then
        StepText := Trimmed(Copy(StepText, 8, MaxInt));
      if Step.IsAttribute and (not IsField or (J <> High(Steps))) then
        Bad;
      Step.Text := StepText;
      if StepText = '*' then
        Step.AnyName := True
      else
      begin
        Prefix := '';
        K := 0;
        for N := 1 to Length(StepText) do
          if StepText[N] = ':' then
          begin
            K := N;
            Break;
          end;
        if K > 0 then
        begin
          Prefix := Copy(StepText, 1, K - 1);
          StepText := Copy(StepText, K + 1, MaxInt);
          if not Node.LookupNamespace(Prefix, Step.NamespaceUri) then
            Fail(Doc, Node, 'the prefix "' + Esc(Prefix) + '" is not declared');
        end;
        { XML Schema 1.0: an unprefixed name has no namespace }
        if StepText = '*' then
          Step.AnyLocalName := True
        else
          Step.LocalName := StepText;
        for N := 1 to Length(StepText) do
          if (StepText[N] = '(') or (StepText[N] = '[') or (StepText[N] = ' ') or (StepText[N] = ':') then
            Bad;
      end;
      SetLength(Path.Steps, Length(Path.Steps) + 1);
      Path.Steps[High(Path.Steps)] := Step;
    end;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Path;
  end;
end;

function TLoader.BuildIdentity(Doc: TSchemaDoc; Node: TLandrixXmlNode): TLandrixXmlXsdIdentityConstraint;
var
  C: TLandrixXmlXsdIdentityConstraint;
  Name, Value, Ns, LocalName: TLandrixXmlUtf8;
  Child: TLandrixXmlNode;
  Fields: TLandrixXmlXsdPathsArray;
  HasSelector: Boolean;
  Fixup: TKeyRefFixup;
begin
  if not AttrTrimmed(Node, 'name', Name) or (Name = '') then
    Fail(Doc, Node, 'an identity constraint without a name');
  C := TLandrixXmlXsdIdentityConstraint.Create;
  FSet.Own(C);
  C.Name := Name;
  C.NamespaceUri := Doc.TargetNamespace;
  C.SchemaFile := Doc.FileName;
  C.SchemaLine := Node.Line;
  if IsXs(Node, 'unique') then
    C.Kind := xikUnique
  else if IsXs(Node, 'key') then
    C.Kind := xikKey
  else
    C.Kind := xikKeyRef;
  if not FIdentity.Add(C.NamespaceUri, C.Name, C) then
    Fail(Doc, Node, 'duplicate identity constraint ' + QualifiedText(C.NamespaceUri, C.Name));
  Fields := nil;
  HasSelector := False;
  Child := Node.FirstChildElement;
  while Child <> nil do
  begin
    if IsXs(Child, 'selector') then
    begin
      if not Attr(Child, 'xpath', Value) then
        Fail(Doc, Child, 'a selector without xpath');
      C.Selector := ParsePaths(Doc, Child, Trimmed(Value), False);
      HasSelector := True;
    end
    else if IsXs(Child, 'field') then
    begin
      if not Attr(Child, 'xpath', Value) then
        Fail(Doc, Child, 'a field without xpath');
      SetLength(Fields, Length(Fields) + 1);
      Fields[High(Fields)] := ParsePaths(Doc, Child, Trimmed(Value), True);
    end
    else if not IsXs(Child, 'annotation') then
      Fail(Doc, Child, 'unexpected element "' + Esc(Child.NameUtf8) + '" in an identity constraint');
    Child := Child.NextSiblingElement;
  end;
  if not HasSelector or (Length(Fields) = 0) then
    Fail(Doc, Node, 'an identity constraint needs a selector and fields');
  C.Fields := Fields;
  if C.Kind = xikKeyRef then
  begin
    if not QNameAttr(Doc, Node, 'refer', Ns, LocalName) then
      Fail(Doc, Node, 'a keyref without refer');
    Fixup := TKeyRefFixup.Create;
    FFixups.Add(Fixup);
    Fixup.Constraint := C;
    Fixup.NamespaceUri := Ns;
    Fixup.Name := LocalName;
    Fixup.FileName := Doc.FileName;
    Fixup.Line := Node.Line;
  end;
  Result := C;
end;

{ --- everything ------------------------------------------------------------ }

procedure TLoader.ResolveAll;
var
  I: Integer;
  P, Saved: TPending;
  Particle: TLandrixXmlXsdParticle;
  Items: TObjectList;
  Wildcard: TLandrixXmlXsdWildcard;
  Fixup: TKeyRefFixup;
  Refer: TLandrixXmlXsdIdentityConstraint;
begin
  { build every declaration, also unused ones, so that unsupported
    constructs are reported wherever they are }
  I := 0;
  while I < FPendings.Count do
  begin
    P := TPending(FPendings[I]);
    case P.Kind of
      pkElement:
        ResolveElement(P);
      pkAttribute:
        ResolveAttribute(P);
      pkComplexType:
        ResolveComplexType(P, True);
      pkSimpleType:
        ResolveSimpleType(P);
      pkGroup:
        begin
          Saved := FCurrent;
          FCurrent := P;
          try
            Particle := EffectiveParticle(P.Doc, P.Node);
            Particle.Free;
          finally
            FCurrent := Saved;
          end;
        end;
      pkAttributeGroup:
        begin
          Items := TObjectList.Create(True);
          Saved := FCurrent;
          FCurrent := P;
          try
            Wildcard := nil;
            CollectAttributes(P.Doc, P.Node, Items, Wildcard);
          finally
            FCurrent := Saved;
            Items.Free;
          end;
        end;
    end;
    Inc(I);
  end;
  for I := 0 to Integer(FFixups.Count) - 1 do
  begin
    Fixup := TKeyRefFixup(FFixups[I]);
    Refer := TLandrixXmlXsdIdentityConstraint(FIdentity.Find(Fixup.NamespaceUri, Fixup.Name));
    if (Refer = nil) or (Refer.Kind = xikKeyRef) then
      raise ELandrixXmlError.CreateCode(xecSchema, 'XML Schema: the keyref ' +
        QualifiedText(Fixup.Constraint.NamespaceUri, Fixup.Constraint.Name) + ' refers to no key ' +
        QualifiedText(Fixup.NamespaceUri, Fixup.Name) + ' in ' + Fixup.FileName + ':' + IntToStr(Fixup.Line));
    if Length(Refer.Fields) <> Length(Fixup.Constraint.Fields) then
      raise ELandrixXmlError.CreateCode(xecSchema, 'XML Schema: the keyref ' +
        QualifiedText(Fixup.Constraint.NamespaceUri, Fixup.Constraint.Name) +
        ' has another number of fields than its key in ' + Fixup.FileName + ':' + IntToStr(Fixup.Line));
    Fixup.Constraint.Refer := Refer;
  end;
end;

{ ---------------------------------------------------------------------- }

function LandrixXmlXsdLoadSchema(const FileName: string;
  Resolver: TLandrixXmlXsdResolver): TLandrixXmlXsdSchemaSet;
var
  Loader: TLoader;
  Own: TLandrixXmlXsdResolver;
begin
  Own := nil;
  if Resolver = nil then
  begin
    Own := TLandrixXmlXsdResolver.Create;
    Resolver := Own;
  end;
  Loader := TLoader.Create(Resolver);
  try
    Result := Loader.Load(FileName);
  finally
    Loader.Free;
    Own.Free;
  end;
end;

end.
