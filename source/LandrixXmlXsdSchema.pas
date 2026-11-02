{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  The components of a loaded XML Schema: element, attribute and type
  declarations, attribute uses, wildcards and identity constraints, all
  resolved (references point to the components, groups and attribute
  groups are expanded). LandrixXmlXsdSchemaLoader builds them;
  LandrixXmlXsdValidator checks documents against them.

  A schema set owns all its components and is not changed after loading,
  so one set can be shared by validators in several threads. Every
  component knows the schema file and line it was declared at. }

unit LandrixXmlXsdSchema;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  Contnrs,
  LandrixXmlBase,
  LandrixXmlXsdTypes,
  LandrixXmlXsdContent;

type
  TLandrixXmlXsdComponent = class
  private
    FNamespaceUri: TLandrixXmlUtf8;
    FName: TLandrixXmlUtf8;
    FSchemaFile: string;
    FSchemaLine: Integer;
  public
    property NamespaceUri: TLandrixXmlUtf8 read FNamespaceUri write FNamespaceUri;
    { '' for an anonymous component }
    property Name: TLandrixXmlUtf8 read FName write FName;
    property SchemaFile: string read FSchemaFile write FSchemaFile;
    property SchemaLine: Integer read FSchemaLine write FSchemaLine;
  end;

  TLandrixXmlXsdProcessContents = (xpcStrict, xpcLax, xpcSkip);

  TLandrixXmlXsdWildcard = class(TLandrixXmlXsdComponent)
  private
    FConstraint: TLandrixXmlXsdNamespaceConstraint;
    FNamespaces: TLandrixXmlUtf8Array;
    FProcessContents: TLandrixXmlXsdProcessContents;
  public
    { Namespaces as for TLandrixXmlXsdParticle.CreateWildcard. }
    procedure SetNamespaces(Constraint: TLandrixXmlXsdNamespaceConstraint;
      const Namespaces: TLandrixXmlUtf8Array);
    function Allows(const NamespaceUri: TLandrixXmlUtf8): Boolean;
    property Constraint: TLandrixXmlXsdNamespaceConstraint read FConstraint;
    property Namespaces: TLandrixXmlUtf8Array read FNamespaces;
    property ProcessContents: TLandrixXmlXsdProcessContents read FProcessContents write FProcessContents;
  end;

  TLandrixXmlXsdValueConstraint = (xvcNone, xvcDefault, xvcFixed);

  TLandrixXmlXsdAttributeDecl = class(TLandrixXmlXsdComponent)
  private
    FSimpleType: TLandrixXmlXsdSimpleType;
    FValueConstraint: TLandrixXmlXsdValueConstraint;
    FConstraintValue: TLandrixXmlUtf8;
    FGlobal: Boolean;
  public
    property SimpleType: TLandrixXmlXsdSimpleType read FSimpleType write FSimpleType;
    property ValueConstraint: TLandrixXmlXsdValueConstraint read FValueConstraint write FValueConstraint;
    { the default or fixed value as written }
    property ConstraintValue: TLandrixXmlUtf8 read FConstraintValue write FConstraintValue;
    property Global: Boolean read FGlobal write FGlobal;
  end;

  { An attribute of a complex type: the declaration and how it is used. }
  TLandrixXmlXsdAttributeUse = class
  private
    FDecl: TLandrixXmlXsdAttributeDecl;
    FRequired: Boolean;
    FValueConstraint: TLandrixXmlXsdValueConstraint;
    FConstraintValue: TLandrixXmlUtf8;
  public
    property Decl: TLandrixXmlXsdAttributeDecl read FDecl write FDecl;
    property Required: Boolean read FRequired write FRequired;
    { the use's own default or fixed value (of a local declaration or a
      reference); the declaration's is in Decl }
    property ValueConstraint: TLandrixXmlXsdValueConstraint read FValueConstraint write FValueConstraint;
    property ConstraintValue: TLandrixXmlUtf8 read FConstraintValue write FConstraintValue;
  end;

  TLandrixXmlXsdContentType = (xctEmpty, xctSimple, xctElementOnly, xctMixed);
  TLandrixXmlXsdDerivation = (xdRestriction, xdExtension);

  TLandrixXmlXsdComplexType = class(TLandrixXmlXsdComponent)
  private
    FDisplayName: TLandrixXmlUtf8;
    FBaseComplex: TLandrixXmlXsdComplexType;
    FBaseSimple: TLandrixXmlXsdSimpleType;
    FDerivation: TLandrixXmlXsdDerivation;
    FAbstract: Boolean;
    FContentType: TLandrixXmlXsdContentType;
    FSimpleType: TLandrixXmlXsdSimpleType;
    FModel: TLandrixXmlXsdContentModel;
    FAttributes: TObjectList;
    FAttributeWildcard: TLandrixXmlXsdWildcard;
    function GetAttributeCount: Integer;
    function GetAttribute(Index: Integer): TLandrixXmlXsdAttributeUse;
    procedure SetModel(Value: TLandrixXmlXsdContentModel);
  public
    constructor Create;
    destructor Destroy; override;
    { Takes ownership of Use. }
    procedure AddAttribute(Use: TLandrixXmlXsdAttributeUse);
    function FindAttribute(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlXsdAttributeUse;
    { the name Xerces prints: the type name or #AnonType_<element> }
    property DisplayName: TLandrixXmlUtf8 read FDisplayName write FDisplayName;
    { the base type: a complex type, or a simple type for simple content
      derived from one }
    property BaseComplex: TLandrixXmlXsdComplexType read FBaseComplex write FBaseComplex;
    property BaseSimple: TLandrixXmlXsdSimpleType read FBaseSimple write FBaseSimple;
    property Derivation: TLandrixXmlXsdDerivation read FDerivation write FDerivation;
    property Abstract: Boolean read FAbstract write FAbstract;
    property ContentType: TLandrixXmlXsdContentType read FContentType write FContentType;
    { the type of the text of simple content }
    property SimpleType: TLandrixXmlXsdSimpleType read FSimpleType write FSimpleType;
    { element-only or mixed content; owned; nil allows no child }
    property Model: TLandrixXmlXsdContentModel read FModel write SetModel;
    property AttributeCount: Integer read GetAttributeCount;
    property Attributes[Index: Integer]: TLandrixXmlXsdAttributeUse read GetAttribute;
    property AttributeWildcard: TLandrixXmlXsdWildcard read FAttributeWildcard write FAttributeWildcard;
  end;

  { A path of an identity constraint's selector or field: steps from the
    context element. Descendant marks a leading ".//". }
  TLandrixXmlXsdPathStep = record
    AnyName: Boolean;
    AnyLocalName: Boolean;
    NamespaceUri: TLandrixXmlUtf8;
    LocalName: TLandrixXmlUtf8;
    IsAttribute: Boolean;
    { the name test as written (prefix:name, prefix:* or *), for messages }
    Text: TLandrixXmlUtf8;
  end;
  TLandrixXmlXsdPathSteps = array of TLandrixXmlXsdPathStep;
  TLandrixXmlXsdPath = record
    Descendant: Boolean;
    Steps: TLandrixXmlXsdPathSteps;
  end;
  { alternatives separated by '|' }
  TLandrixXmlXsdPaths = array of TLandrixXmlXsdPath;
  TLandrixXmlXsdPathsArray = array of TLandrixXmlXsdPaths;

  TLandrixXmlXsdIdentityKind = (xikUnique, xikKey, xikKeyRef);

  TLandrixXmlXsdIdentityConstraint = class(TLandrixXmlXsdComponent)
  private
    FKind: TLandrixXmlXsdIdentityKind;
    FRefer: TLandrixXmlXsdIdentityConstraint;
    FSelector: TLandrixXmlXsdPaths;
    FFields: TLandrixXmlXsdPathsArray;
  public
    property Kind: TLandrixXmlXsdIdentityKind read FKind write FKind;
    { the key or unique constraint a keyref refers to }
    property Refer: TLandrixXmlXsdIdentityConstraint read FRefer write FRefer;
    property Selector: TLandrixXmlXsdPaths read FSelector write FSelector;
    property Fields: TLandrixXmlXsdPathsArray read FFields write FFields;
  end;

  TLandrixXmlXsdElementDecl = class(TLandrixXmlXsdComponent)
  private
    FSimpleType: TLandrixXmlXsdSimpleType;
    FComplexType: TLandrixXmlXsdComplexType;
    FValueConstraint: TLandrixXmlXsdValueConstraint;
    FConstraintValue: TLandrixXmlUtf8;
    FGlobal: Boolean;
    FConstraints: TList;
    function GetConstraintCount: Integer;
    function GetConstraint(Index: Integer): TLandrixXmlXsdIdentityConstraint;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddConstraint(Constraint: TLandrixXmlXsdIdentityConstraint);
    { exactly one of SimpleType and ComplexType is set }
    property SimpleType: TLandrixXmlXsdSimpleType read FSimpleType write FSimpleType;
    property ComplexType: TLandrixXmlXsdComplexType read FComplexType write FComplexType;
    property ValueConstraint: TLandrixXmlXsdValueConstraint read FValueConstraint write FValueConstraint;
    property ConstraintValue: TLandrixXmlUtf8 read FConstraintValue write FConstraintValue;
    property Global: Boolean read FGlobal write FGlobal;
    property ConstraintCount: Integer read GetConstraintCount;
    property Constraints[Index: Integer]: TLandrixXmlXsdIdentityConstraint read GetConstraint;
  end;

  { UTF-8 names to objects (internal; public only because Delphi 6 has no
    nested types). }
  TLandrixXmlXsdNameMapEntry = record
    Key: TLandrixXmlUtf8;
    Value: TObject;
  end;
  TLandrixXmlXsdNameMapEntries = array of TLandrixXmlXsdNameMapEntry;

  TLandrixXmlXsdNameMap = class
  private
    FEntries: TLandrixXmlXsdNameMapEntries;
    FCount: Integer;
    function Slot(const Key: TLandrixXmlUtf8): Integer;
    procedure Grow;
  public
    { False if the key is present already (the value is not replaced). }
    function Add(const NamespaceUri, LocalName: TLandrixXmlUtf8; Value: TObject): Boolean;
    procedure Put(const NamespaceUri, LocalName: TLandrixXmlUtf8; Value: TObject);
    function Find(const NamespaceUri, LocalName: TLandrixXmlUtf8): TObject;
    property Count: Integer read FCount;
  end;

  TLandrixXmlXsdSchemaSet = class
  private
    FOwned: TObjectList;
    FElements: TLandrixXmlXsdNameMap;
    FAttributes: TLandrixXmlXsdNameMap;
    FComplexTypes: TLandrixXmlXsdNameMap;
    FSimpleTypes: TLandrixXmlXsdNameMap;
    FAnyType: TLandrixXmlXsdComplexType;
    FFiles: TStringList;
    FWarnings: TStringList;
    FEntryFile: string;
  public
    constructor Create;
    destructor Destroy; override;
    { Takes ownership of a component, simple type or content model. }
    procedure Own(AObject: TObject);
    function FindElement(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlXsdElementDecl;
    function FindAttribute(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlXsdAttributeDecl;
    function FindComplexType(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlXsdComplexType;
    { schema-defined simple types; built-in types come from
      LandrixXmlXsdBuiltinType }
    function FindSimpleType(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlXsdSimpleType;
    { the global component tables, filled by the loader }
    property Elements: TLandrixXmlXsdNameMap read FElements;
    property Attributes: TLandrixXmlXsdNameMap read FAttributes;
    property ComplexTypes: TLandrixXmlXsdNameMap read FComplexTypes;
    property SimpleTypes: TLandrixXmlXsdNameMap read FSimpleTypes;
    { xs:anyType: mixed content of any elements (lax), any attributes (lax) }
    property AnyType: TLandrixXmlXsdComplexType read FAnyType;
    { the schema documents that were read, entry document first }
    property Files: TStringList read FFiles;
    { one line per include, redefine or import (with a schemaLocation
      attribute) whose document could not be found and was skipped }
    property Warnings: TStringList read FWarnings;
    property EntryFile: string read FEntryFile write FEntryFile;
  end;

implementation

{ ---------------------------------------------------------------------- }
{ TLandrixXmlXsdWildcard                                                 }
{ ---------------------------------------------------------------------- }

procedure TLandrixXmlXsdWildcard.SetNamespaces(Constraint: TLandrixXmlXsdNamespaceConstraint;
  const Namespaces: TLandrixXmlUtf8Array);
var
  I: Integer;
begin
  FConstraint := Constraint;
  FNamespaces := nil;
  SetLength(FNamespaces, Length(Namespaces));
  for I := 0 to Integer(Length(Namespaces)) - 1 do
    FNamespaces[I] := Namespaces[I];
end;

function TLandrixXmlXsdWildcard.Allows(const NamespaceUri: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := False;
  case FConstraint of
    xncAny:
      Result := True;
    xncNot:
      Result := (NamespaceUri <> '') and (NamespaceUri <> FNamespaces[0]);
    xncList:
      for I := 0 to Integer(Length(FNamespaces)) - 1 do
        if FNamespaces[I] = NamespaceUri then
        begin
          Result := True;
          Exit;
        end;
  end;
end;

{ ---------------------------------------------------------------------- }
{ TLandrixXmlXsdComplexType                                              }
{ ---------------------------------------------------------------------- }

constructor TLandrixXmlXsdComplexType.Create;
begin
  inherited Create;
  FAttributes := TObjectList.Create(True);
end;

destructor TLandrixXmlXsdComplexType.Destroy;
begin
  FAttributes.Free;
  FModel.Free;
  inherited Destroy;
end;

procedure TLandrixXmlXsdComplexType.SetModel(Value: TLandrixXmlXsdContentModel);
begin
  if Value <> FModel then
  begin
    FModel.Free;
    FModel := Value;
  end;
end;

procedure TLandrixXmlXsdComplexType.AddAttribute(Use: TLandrixXmlXsdAttributeUse);
begin
  FAttributes.Add(Use);
end;

function TLandrixXmlXsdComplexType.FindAttribute(const NamespaceUri,
  LocalName: TLandrixXmlUtf8): TLandrixXmlXsdAttributeUse;
var
  I: Integer;
begin
  for I := 0 to Integer(FAttributes.Count) - 1 do
  begin
    Result := TLandrixXmlXsdAttributeUse(FAttributes[I]);
    if (Result.Decl.Name = LocalName) and (Result.Decl.NamespaceUri = NamespaceUri) then
      Exit;
  end;
  Result := nil;
end;

function TLandrixXmlXsdComplexType.GetAttributeCount: Integer;
begin
  Result := Integer(FAttributes.Count);
end;

function TLandrixXmlXsdComplexType.GetAttribute(Index: Integer): TLandrixXmlXsdAttributeUse;
begin
  Result := TLandrixXmlXsdAttributeUse(FAttributes[Index]);
end;

{ ---------------------------------------------------------------------- }
{ TLandrixXmlXsdElementDecl                                              }
{ ---------------------------------------------------------------------- }

constructor TLandrixXmlXsdElementDecl.Create;
begin
  inherited Create;
  FConstraints := TList.Create;
end;

destructor TLandrixXmlXsdElementDecl.Destroy;
begin
  FConstraints.Free;
  inherited Destroy;
end;

procedure TLandrixXmlXsdElementDecl.AddConstraint(Constraint: TLandrixXmlXsdIdentityConstraint);
begin
  FConstraints.Add(Constraint);
end;

function TLandrixXmlXsdElementDecl.GetConstraintCount: Integer;
begin
  Result := Integer(FConstraints.Count);
end;

function TLandrixXmlXsdElementDecl.GetConstraint(Index: Integer): TLandrixXmlXsdIdentityConstraint;
begin
  Result := TLandrixXmlXsdIdentityConstraint(FConstraints[Index]);
end;

{ ---------------------------------------------------------------------- }
{ TLandrixXmlXsdNameMap                                                  }
{ ---------------------------------------------------------------------- }

function MapKey(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlUtf8;
begin
  { names never contain a TAB, so it cannot be part of either }
  Result := NamespaceUri + #9 + LocalName;
end;

function HashOf(const Key: TLandrixXmlUtf8): Cardinal;
var
  I: Integer;
begin
  { FNV-1a; the product fits in Int64, so overflow checks stay quiet }
  Result := 2166136261;
  for I := 1 to Length(Key) do
    Result := Cardinal((Int64(Result xor Cardinal(Ord(Key[I]))) * 16777619) and $FFFFFFFF);
end;

{ The slot of Key, or of the empty slot where it would go. }
function TLandrixXmlXsdNameMap.Slot(const Key: TLandrixXmlUtf8): Integer;
var
  Mask: Integer;
begin
  Mask := Integer(Length(FEntries)) - 1;
  Result := Integer(HashOf(Key) and Cardinal(Mask));
  while (FEntries[Result].Value <> nil) and (FEntries[Result].Key <> Key) do
    Result := (Result + 1) and Mask;
end;

procedure TLandrixXmlXsdNameMap.Grow;
var
  Old: TLandrixXmlXsdNameMapEntries;
  I, S: Integer;
begin
  Old := FEntries;
  FEntries := nil;
  if Length(Old) = 0 then
    SetLength(FEntries, 64)
  else
    SetLength(FEntries, 2 * Length(Old));
  for I := 0 to Integer(Length(Old)) - 1 do
    if Old[I].Value <> nil then
    begin
      S := Slot(Old[I].Key);
      FEntries[S] := Old[I];
    end;
end;

function TLandrixXmlXsdNameMap.Add(const NamespaceUri, LocalName: TLandrixXmlUtf8;
  Value: TObject): Boolean;
var
  Key: TLandrixXmlUtf8;
  S: Integer;
begin
  if Value = nil then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'A name map entry needs a value');
  if 2 * (FCount + 1) > Length(FEntries) then
    Grow;
  Key := MapKey(NamespaceUri, LocalName);
  S := Slot(Key);
  Result := FEntries[S].Value = nil;
  if Result then
  begin
    FEntries[S].Key := Key;
    FEntries[S].Value := Value;
    Inc(FCount);
  end;
end;

procedure TLandrixXmlXsdNameMap.Put(const NamespaceUri, LocalName: TLandrixXmlUtf8; Value: TObject);
var
  S: Integer;
begin
  if not Add(NamespaceUri, LocalName, Value) then
  begin
    S := Slot(MapKey(NamespaceUri, LocalName));
    FEntries[S].Value := Value;
  end;
end;

function TLandrixXmlXsdNameMap.Find(const NamespaceUri, LocalName: TLandrixXmlUtf8): TObject;
begin
  Result := nil;
  if FCount = 0 then
    Exit;
  Result := FEntries[Slot(MapKey(NamespaceUri, LocalName))].Value;
end;

{ ---------------------------------------------------------------------- }
{ TLandrixXmlXsdSchemaSet                                                }
{ ---------------------------------------------------------------------- }

constructor TLandrixXmlXsdSchemaSet.Create;
var
  Root: TLandrixXmlXsdParticle;
  Wildcard: TLandrixXmlXsdWildcard;
  None: TLandrixXmlUtf8Array;
begin
  inherited Create;
  FOwned := TObjectList.Create(True);
  FElements := TLandrixXmlXsdNameMap.Create;
  FAttributes := TLandrixXmlXsdNameMap.Create;
  FComplexTypes := TLandrixXmlXsdNameMap.Create;
  FSimpleTypes := TLandrixXmlXsdNameMap.Create;
  FFiles := TStringList.Create;
  FWarnings := TStringList.Create;
  { xs:anyType }
  None := nil;
  FAnyType := TLandrixXmlXsdComplexType.Create;
  FAnyType.NamespaceUri := LandrixXmlXsdNamespace;
  FAnyType.Name := 'anyType';
  FAnyType.DisplayName := 'anyType';
  FAnyType.ContentType := xctMixed;
  Wildcard := TLandrixXmlXsdWildcard.Create;
  Wildcard.SetNamespaces(xncAny, None);
  Wildcard.ProcessContents := xpcLax;
  Own(Wildcard);
  Root := TLandrixXmlXsdParticle.CreateGroup(xpkSequence, 1, 1);
  Root.Add(TLandrixXmlXsdParticle.CreateWildcard(xncAny, None, Wildcard, 0, LandrixXmlXsdUnbounded));
  FAnyType.Model := TLandrixXmlXsdContentModel.Create(Root);
  FAnyType.AttributeWildcard := Wildcard;
  Own(FAnyType);
  FComplexTypes.Add(LandrixXmlXsdNamespace, 'anyType', FAnyType);
end;

destructor TLandrixXmlXsdSchemaSet.Destroy;
begin
  FElements.Free;
  FAttributes.Free;
  FComplexTypes.Free;
  FSimpleTypes.Free;
  FFiles.Free;
  FWarnings.Free;
  FOwned.Free;
  inherited Destroy;
end;

procedure TLandrixXmlXsdSchemaSet.Own(AObject: TObject);
begin
  FOwned.Add(AObject);
end;

function TLandrixXmlXsdSchemaSet.FindElement(const NamespaceUri,
  LocalName: TLandrixXmlUtf8): TLandrixXmlXsdElementDecl;
begin
  Result := TLandrixXmlXsdElementDecl(FElements.Find(NamespaceUri, LocalName));
end;

function TLandrixXmlXsdSchemaSet.FindAttribute(const NamespaceUri,
  LocalName: TLandrixXmlUtf8): TLandrixXmlXsdAttributeDecl;
begin
  Result := TLandrixXmlXsdAttributeDecl(FAttributes.Find(NamespaceUri, LocalName));
end;

function TLandrixXmlXsdSchemaSet.FindComplexType(const NamespaceUri,
  LocalName: TLandrixXmlUtf8): TLandrixXmlXsdComplexType;
begin
  Result := TLandrixXmlXsdComplexType(FComplexTypes.Find(NamespaceUri, LocalName));
end;

function TLandrixXmlXsdSchemaSet.FindSimpleType(const NamespaceUri,
  LocalName: TLandrixXmlUtf8): TLandrixXmlXsdSimpleType;
begin
  Result := TLandrixXmlXsdSimpleType(FSimpleTypes.Find(NamespaceUri, LocalName));
end;

end.
