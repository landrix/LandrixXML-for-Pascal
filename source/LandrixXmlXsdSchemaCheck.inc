{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Part of LandrixXmlXsdSchemaLoader: checks a schema document against the
  rules of the schema for schemas of XML Schema 1.0 before its components
  are collected: the attributes each schema element may have and the
  types of their values, the elements it may contain and their order, no
  character data outside xs:appinfo and xs:documentation, and no id twice
  in a document. Attributes in other namespaces are allowed everywhere;
  xml:lang on xs:schema and xs:documentation must be a language. A
  local element or attribute with ref has the attributes of a
  reference only.
  The errors carry the code Xerces reports (s4s-att-not-allowed,
  s4s-att-must-appear, s4s-att-invalid-value, s4s-elt-must-match.1,
  s4s-elt-invalid-content.1, s4s-elt-character). Included in the
  implementation section.
  Xerces deviation: vc001, vc002, vc024. The version attributes
  (vc:minVersion and the like) are not evaluated, so XSD 1.1 elements
  they would exclude are errors. }

type
  { The rule of one kind of schema element. Attributes: names with the
    type of their value ("name=NCName"), separated by spaces, "!" before
    a required one. Content: steps separated by ";", each a set of
    element names separated by "|" and a quantifier ("?", "*", "+" or
    none for exactly one); alternatives separated by "/"; "*" alone for
    any content (not checked). }
  TSchemaRule = record
    Kind: TLandrixXmlUtf8;
    Attributes: TLandrixXmlUtf8;
    Content: TLandrixXmlUtf8;
  end;

const
  FacetNames = 'minExclusive|minInclusive|maxExclusive|maxInclusive|totalDigits|fractionDigits|length|' +
    'minLength|maxLength|enumeration|whiteSpace|pattern';
  OccursAttributes = 'minOccurs=nonNegativeInteger maxOccurs=allNNI';

  SchemaRuleCount = 44;
  SchemaRules: array[0..SchemaRuleCount - 1] of TSchemaRule = (
    (Kind: 'schema';
     Attributes: 'targetNamespace=anyURI version=token finalDefault=fullDerivationSet blockDefault=blockSet ' +
       'attributeFormDefault=form elementFormDefault=form id=ID';
     Content: 'include|import|redefine|annotation*;' +
       'simpleType|complexType|group|attributeGroup|element|attribute|notation|annotation*'),
    (Kind: 'annotation'; Attributes: 'id=ID'; Content: 'appinfo|documentation*'),
    (Kind: 'appinfo'; Attributes: 'source=anyURI'; Content: '*'),
    (Kind: 'documentation'; Attributes: 'source=anyURI'; Content: '*'),
    (Kind: 'include'; Attributes: '!schemaLocation=anyURI id=ID'; Content: 'annotation?'),
    (Kind: 'import'; Attributes: 'namespace=anyURI schemaLocation=anyURI id=ID'; Content: 'annotation?'),
    (Kind: 'redefine'; Attributes: '!schemaLocation=anyURI id=ID';
     Content: 'annotation|simpleType|complexType|group|attributeGroup*'),
    (Kind: 'notation'; Attributes: '!name=NCName public=token system=anyURI id=ID'; Content: 'annotation?'),
    (Kind: 'element.top';
     Attributes: '!name=NCName type=QName substitutionGroup=QName default=string fixed=string ' +
       'nillable=boolean abstract=boolean final=derivationSet block=blockSet id=ID';
     Content: 'annotation?;simpleType|complexType?;unique|key|keyref*'),
    (Kind: 'element.local';
     Attributes: 'name=NCName ref=QName type=QName default=string fixed=string nillable=boolean ' +
       'block=blockSet form=form ' + OccursAttributes + ' id=ID';
     Content: 'annotation?;simpleType|complexType?;unique|key|keyref*'),
    (Kind: 'element.all';
     Attributes: 'name=NCName ref=QName type=QName default=string fixed=string nillable=boolean ' +
       'block=blockSet form=form minOccurs=zeroOrOne maxOccurs=zeroOrOne id=ID';
     Content: 'annotation?;simpleType|complexType?;unique|key|keyref*'),
    (Kind: 'element.ref'; Attributes: 'ref=QName ' + OccursAttributes + ' id=ID'; Content: 'annotation?'),
    (Kind: 'element.allref'; Attributes: 'ref=QName minOccurs=zeroOrOne maxOccurs=zeroOrOne id=ID';
     Content: 'annotation?'),
    (Kind: 'attribute.ref'; Attributes: 'ref=QName use=use default=string fixed=string id=ID';
     Content: 'annotation?'),
    (Kind: 'attribute.top'; Attributes: '!name=NCName type=QName default=string fixed=string id=ID';
     Content: 'annotation?;simpleType?'),
    (Kind: 'attribute.local';
     Attributes: 'name=NCName ref=QName type=QName use=use default=string fixed=string form=form id=ID';
     Content: 'annotation?;simpleType?'),
    (Kind: 'complexType.top';
     Attributes: '!name=NCName mixed=boolean abstract=boolean final=derivationSet block=derivationSet id=ID';
     Content: 'annotation?;simpleContent|complexContent/' +
       'annotation?;group|all|choice|sequence?;attribute|attributeGroup*;anyAttribute?'),
    (Kind: 'complexType.local'; Attributes: 'mixed=boolean id=ID';
     Content: 'annotation?;simpleContent|complexContent/' +
       'annotation?;group|all|choice|sequence?;attribute|attributeGroup*;anyAttribute?'),
    (Kind: 'simpleContent'; Attributes: 'id=ID'; Content: 'annotation?;restriction|extension'),
    (Kind: 'complexContent'; Attributes: 'mixed=boolean id=ID'; Content: 'annotation?;restriction|extension'),
    (Kind: 'restriction.sc'; Attributes: '!base=QName id=ID';
     Content: 'annotation?;simpleType?;' + FacetNames + '*;attribute|attributeGroup*;anyAttribute?'),
    (Kind: 'extension.sc'; Attributes: '!base=QName id=ID';
     Content: 'annotation?;attribute|attributeGroup*;anyAttribute?'),
    (Kind: 'restriction.cc'; Attributes: '!base=QName id=ID';
     Content: 'annotation?;group|all|choice|sequence?;attribute|attributeGroup*;anyAttribute?'),
    (Kind: 'extension.cc'; Attributes: '!base=QName id=ID';
     Content: 'annotation?;group|all|choice|sequence?;attribute|attributeGroup*;anyAttribute?'),
    (Kind: 'simpleType.top'; Attributes: '!name=NCName final=simpleDerivationSet id=ID';
     Content: 'annotation?;restriction|list|union'),
    (Kind: 'simpleType.local'; Attributes: 'id=ID'; Content: 'annotation?;restriction|list|union'),
    (Kind: 'restriction.simple'; Attributes: 'base=QName id=ID';
     Content: 'annotation?;simpleType?;' + FacetNames + '*'),
    (Kind: 'list'; Attributes: 'itemType=QName id=ID'; Content: 'annotation?;simpleType?'),
    (Kind: 'union'; Attributes: 'memberTypes=QNames id=ID'; Content: 'annotation?;simpleType*'),
    (Kind: 'group.top'; Attributes: '!name=NCName id=ID'; Content: 'annotation?;all|choice|sequence'),
    (Kind: 'group.ref'; Attributes: '!ref=QName ' + OccursAttributes + ' id=ID'; Content: 'annotation?'),
    (Kind: 'attributeGroup.top'; Attributes: '!name=NCName id=ID';
     Content: 'annotation?;attribute|attributeGroup*;anyAttribute?'),
    (Kind: 'attributeGroup.ref'; Attributes: '!ref=QName id=ID'; Content: 'annotation?'),
    (Kind: 'compositor'; Attributes: OccursAttributes + ' id=ID';
     Content: 'annotation?;element|group|choice|sequence|any*'),
    (Kind: 'compositor.top'; Attributes: 'id=ID'; Content: 'annotation?;element|group|choice|sequence|any*'),
    (Kind: 'all'; Attributes: 'minOccurs=zeroOrOne maxOccurs=one id=ID'; Content: 'annotation?;element*'),
    (Kind: 'all.top'; Attributes: 'id=ID'; Content: 'annotation?;element*'),
    { Xerces deviation: s3_10_1ii08, s3_10_6ii01, s3_10_6ii02, s3_10_6ii04.
      No notNamespace and notQName (XSD 1.1) on the wildcards }
    (Kind: 'any';
     Attributes: 'namespace=namespaceList processContents=processContents ' + OccursAttributes + ' id=ID';
     Content: 'annotation?'),
    (Kind: 'anyAttribute'; Attributes: 'namespace=namespaceList processContents=processContents id=ID';
     Content: 'annotation?'),
    (Kind: 'facet'; Attributes: '!value=string fixed=boolean id=ID'; Content: 'annotation?'),
    (Kind: 'facet.count'; Attributes: '!value=nonNegativeInteger fixed=boolean id=ID'; Content: 'annotation?'),
    (Kind: 'facet.digits'; Attributes: '!value=positiveInteger fixed=boolean id=ID'; Content: 'annotation?'),
    (Kind: 'facet.notfixed'; Attributes: '!value=string id=ID'; Content: 'annotation?'),
    (Kind: 'facet.whiteSpace'; Attributes: '!value=whiteSpace fixed=boolean id=ID'; Content: 'annotation?')
  );

  { the identity constraints and their parts }
  SchemaKeyRules: array[0..2] of TSchemaRule = (
    (Kind: 'key'; Attributes: '!name=NCName id=ID'; Content: 'annotation?;selector;field+'),
    (Kind: 'keyref'; Attributes: '!name=NCName !refer=QName id=ID'; Content: 'annotation?;selector;field+'),
    (Kind: 'path'; Attributes: '!xpath=string id=ID'; Content: 'annotation?')
  );

{ The kind of a schema element from its local name and its parent's
  kind; '' if there is no rule (the parent's content check rejects it). }
function SchemaKindOf(const LocalName, ParentKind: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  TopLevel: Boolean;
begin
  TopLevel := (ParentKind = 'schema') or (ParentKind = 'redefine');
  Result := '';
  if (LocalName = 'annotation') or (LocalName = 'appinfo') or (LocalName = 'documentation') or
    (LocalName = 'include') or (LocalName = 'import') or (LocalName = 'redefine') or
    (LocalName = 'notation') or (LocalName = 'simpleContent') or (LocalName = 'complexContent') or
    (LocalName = 'list') or (LocalName = 'union') or (LocalName = 'any') or (LocalName = 'anyAttribute') or
    (LocalName = 'keyref') then
    Result := LocalName
  else if LocalName = 'element' then
  begin
    if ParentKind = 'schema' then
      Result := 'element.top'
    else if (ParentKind = 'all') or (ParentKind = 'all.top') then
      Result := 'element.all'
    else
      Result := 'element.local';
  end
  else if LocalName = 'attribute' then
  begin
    if ParentKind = 'schema' then
      Result := 'attribute.top'
    else
      Result := 'attribute.local';
  end
  else if (LocalName = 'complexType') or (LocalName = 'simpleType') or (LocalName = 'attributeGroup') then
  begin
    if TopLevel then
      Result := LocalName + '.top'
    else if LocalName = 'attributeGroup' then
      Result := LocalName + '.ref'
    else
      Result := LocalName + '.local';
  end
  else if LocalName = 'group' then
  begin
    if TopLevel then
      Result := 'group.top'
    else
      Result := 'group.ref';
  end
  else if (LocalName = 'sequence') or (LocalName = 'choice') then
  begin
    if ParentKind = 'group.top' then
      Result := 'compositor.top'
    else
      Result := 'compositor';
  end
  else if LocalName = 'all' then
  begin
    if ParentKind = 'group.top' then
      Result := 'all.top'
    else
      Result := 'all';
  end
  else if LocalName = 'restriction' then
  begin
    if ParentKind = 'simpleContent' then
      Result := 'restriction.sc'
    else if ParentKind = 'complexContent' then
      Result := 'restriction.cc'
    else
      Result := 'restriction.simple';
  end
  else if LocalName = 'extension' then
  begin
    if ParentKind = 'simpleContent' then
      Result := 'extension.sc'
    else
      Result := 'extension.cc';
  end
  else if (LocalName = 'unique') or (LocalName = 'key') then
    Result := 'key'
  else if (LocalName = 'selector') or (LocalName = 'field') then
    Result := 'path'
  else if (LocalName = 'minExclusive') or (LocalName = 'minInclusive') or (LocalName = 'maxExclusive') or
    (LocalName = 'maxInclusive') then
    Result := 'facet'
  else if (LocalName = 'fractionDigits') or (LocalName = 'length') or (LocalName = 'minLength') or
    (LocalName = 'maxLength') then
    Result := 'facet.count'
  else if LocalName = 'totalDigits' then
    Result := 'facet.digits'
  else if (LocalName = 'enumeration') or (LocalName = 'pattern') then
    Result := 'facet.notfixed'
  else if LocalName = 'whiteSpace' then
    Result := 'facet.whiteSpace';
end;

function SchemaRuleOf(const Kind: TLandrixXmlUtf8; out Rule: TSchemaRule): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 0 to SchemaRuleCount - 1 do
    if SchemaRules[I].Kind = Kind then
    begin
      Rule := SchemaRules[I];
      Exit;
    end;
  for I := 0 to 2 do
    if SchemaKeyRules[I].Kind = Kind then
    begin
      Rule := SchemaKeyRules[I];
      Exit;
    end;
  Result := False;
end;

{ The next token of S from position P up to Sep (or the end); P moves
  past the separator. }
function NextToken(const S: TLandrixXmlUtf8; var P: Integer; Sep: AnsiChar): TLandrixXmlUtf8;
var
  Start: Integer;
begin
  Start := P;
  while (P <= Length(S)) and (AnsiChar(S[P]) <> Sep) do
    Inc(P);
  Result := Copy(S, Start, P - Start);
  Inc(P);
end;

{ True if Name is one of the Sep-separated names in List. }
function InNameList(const Name, List: TLandrixXmlUtf8; Sep: AnsiChar): Boolean;
var
  P: Integer;
begin
  P := 1;
  while P <= Length(List) do
    if NextToken(List, P, Sep) = Name then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

{ The position of C in S, 0 if it does not occur (bytes, no string
  conversion). }
function CharPos(C: AnsiChar; const S: TLandrixXmlUtf8): Integer;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    if AnsiChar(S[I]) = C then
    begin
      Result := I;
      Exit;
    end;
  Result := 0;
end;

function ValidBuiltin(const TypeName, Value: TLandrixXmlUtf8): Boolean;
var
  V: TLandrixXmlXsdValue;
  E: TLandrixXmlXsdError;
begin
  Result := LandrixXmlXsdBuiltinType(TypeName).Validate(Value, V, E);
end;

function ValidQName(const Value: TLandrixXmlUtf8): Boolean;
var
  S: TLandrixXmlUtf8;
  P: Integer;
begin
  S := LandrixXmlXsdNormalizeWhiteSpace(Value, xwsCollapse);
  { the parts must not be trimmed again ("xs: string" is no QName) }
  if CharPos(' ', S) > 0 then
  begin
    Result := False;
    Exit;
  end;
  P := CharPos(':', S);
  if P = 0 then
    Result := ValidBuiltin('NCName', S)
  else
    Result := ValidBuiltin('NCName', Copy(S, 1, P - 1)) and ValidBuiltin('NCName', Copy(S, P + 1, MaxInt));
end;

{ "#all", or a list of names from Allowed (comma-separated); empty is
  allowed. }
function ValidDerivationSet(const Value, Allowed: TLandrixXmlUtf8): Boolean;
var
  S, Item: TLandrixXmlUtf8;
  P: Integer;
begin
  S := LandrixXmlXsdNormalizeWhiteSpace(Value, xwsCollapse);
  Result := True;
  if S = '#all' then
    Exit;
  P := 1;
  while P <= Length(S) do
  begin
    Item := NextToken(S, P, ' ');
    if not InNameList(Item, Allowed, ',') then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

{ 0 or 1 as a nonNegativeInteger, or (OnlyOne) exactly 1. }
function ValidSmallCount(const Value: TLandrixXmlUtf8; OnlyOne: Boolean): Boolean;
var
  S: TLandrixXmlUtf8;
  P: Integer;
begin
  Result := ValidBuiltin('nonNegativeInteger', Value);
  if not Result then
    Exit;
  S := LandrixXmlXsdNormalizeWhiteSpace(Value, xwsCollapse);
  P := 1;
  { a valid nonNegativeInteger with "-" is zero ("-0") }
  if (S <> '') and ((S[1] = '+') or (S[1] = '-')) then
    P := 2;
  while (P < Length(S)) and (S[P] = '0') do
    Inc(P);
  S := Copy(S, P, MaxInt);
  if OnlyOne then
    Result := S = '1'
  else
    Result := (S = '0') or (S = '1');
end;

function ValidNamespaceList(const Value: TLandrixXmlUtf8): Boolean;
var
  S, Item: TLandrixXmlUtf8;
  P: Integer;
begin
  S := LandrixXmlXsdNormalizeWhiteSpace(Value, xwsCollapse);
  Result := True;
  if (S = '##any') or (S = '##other') then
    Exit;
  P := 1;
  while P <= Length(S) do
  begin
    Item := NextToken(S, P, ' ');
    if (Item = '##targetNamespace') or (Item = '##local') then
      Continue;
    if (Copy(Item, 1, 2) = '##') or not ValidBuiltin('anyURI', Item) then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

{ Checks Value against a value type of the rule table. }
function ValidSchemaValue(const TypeName, Value: TLandrixXmlUtf8): Boolean;
var
  S: TLandrixXmlUtf8;
  P: Integer;
begin
  if TypeName = 'string' then
    Result := True
  else if TypeName = 'ID' then
    Result := ValidBuiltin('NCName', Value)
  else if TypeName = 'QName' then
    Result := ValidQName(Value)
  else if TypeName = 'QNames' then
  begin
    S := LandrixXmlXsdNormalizeWhiteSpace(Value, xwsCollapse);
    Result := True;
    P := 1;
    while Result and (P <= Length(S)) do
      Result := ValidQName(NextToken(S, P, ' '));
  end
  else if TypeName = 'allNNI' then
    Result := (LandrixXmlXsdNormalizeWhiteSpace(Value, xwsCollapse) = 'unbounded') or
      ValidBuiltin('nonNegativeInteger', Value)
  else if TypeName = 'zeroOrOne' then
    Result := ValidSmallCount(Value, False)
  else if TypeName = 'one' then
    Result := ValidSmallCount(Value, True)
  else if TypeName = 'form' then
    Result := InNameList(LandrixXmlXsdNormalizeWhiteSpace(Value, xwsCollapse), 'qualified,unqualified', ',')
  else if TypeName = 'use' then
    Result := InNameList(LandrixXmlXsdNormalizeWhiteSpace(Value, xwsCollapse), 'prohibited,optional,required', ',')
  else if TypeName = 'processContents' then
    Result := InNameList(LandrixXmlXsdNormalizeWhiteSpace(Value, xwsCollapse), 'skip,lax,strict', ',')
  else if TypeName = 'whiteSpace' then
    Result := InNameList(LandrixXmlXsdNormalizeWhiteSpace(Value, xwsCollapse), 'preserve,replace,collapse', ',')
  else if TypeName = 'derivationSet' then
    Result := ValidDerivationSet(Value, 'extension,restriction')
  else if TypeName = 'blockSet' then
    Result := ValidDerivationSet(Value, 'extension,restriction,substitution')
  else if TypeName = 'fullDerivationSet' then
    Result := ValidDerivationSet(Value, 'extension,restriction,list,union')
  else if TypeName = 'simpleDerivationSet' then
    Result := ValidDerivationSet(Value, 'list,union,restriction')
  else if TypeName = 'namespaceList' then
    Result := ValidNamespaceList(Value)
  else
    { NCName, anyURI, boolean, token, nonNegativeInteger, positiveInteger }
    Result := ValidBuiltin(TypeName, Value);
end;

{ The type of attribute Name in the rule's attribute list, '' if it is
  not allowed. }
function SchemaAttributeType(const Attributes, Name: TLandrixXmlUtf8): TLandrixXmlUtf8;
var
  P, Q: Integer;
  Item: TLandrixXmlUtf8;
begin
  P := 1;
  while P <= Length(Attributes) do
  begin
    Item := NextToken(Attributes, P, ' ');
    if (Item <> '') and (Item[1] = '!') then
      Item := Copy(Item, 2, MaxInt);
    Q := CharPos('=', Item);
    if Copy(Item, 1, Q - 1) = Name then
    begin
      Result := Copy(Item, Q + 1, MaxInt);
      Exit;
    end;
  end;
  Result := '';
end;

{ Matches the names of the element children against one alternative of a
  content model: -1 if they match, else the index of the first child that
  does not fit (Count if a required element is missing). }
function MatchSchemaSteps(const Steps: TLandrixXmlUtf8; const Names: TLandrixXmlUtf8Array;
  Count: Integer): Integer;
var
  P, I, N, MinCount, MaxCount: Integer;
  Step: TLandrixXmlUtf8;
  Q: AnsiChar;
begin
  I := 0;
  P := 1;
  while P <= Length(Steps) do
  begin
    Step := NextToken(Steps, P, ';');
    Q := AnsiChar(Step[Length(Step)]);
    MinCount := 1;
    MaxCount := 1;
    if Q = '?' then
      MinCount := 0
    else if Q = '*' then
    begin
      MinCount := 0;
      MaxCount := MaxInt;
    end
    else if Q = '+' then
      MaxCount := MaxInt;
    if (Q = '?') or (Q = '*') or (Q = '+') then
      Step := Copy(Step, 1, Length(Step) - 1);
    N := 0;
    while (I < Count) and (N < MaxCount) and InNameList(Names[I], Step, '|') do
    begin
      Inc(I);
      Inc(N);
    end;
    if N < MinCount then
    begin
      Result := I;
      Exit;
    end;
  end;
  if I < Count then
    Result := I
  else
    Result := -1;
end;

{ All alternatives: -1 if one matches, else the furthest failure. }
function MatchSchemaContent(const Content: TLandrixXmlUtf8; const Names: TLandrixXmlUtf8Array;
  Count: Integer): Integer;
var
  P, R: Integer;
begin
  Result := 0;
  P := 1;
  while P <= Length(Content) do
  begin
    R := MatchSchemaSteps(NextToken(Content, P, '/'), Names, Count);
    if R < 0 then
    begin
      Result := -1;
      Exit;
    end;
    if R > Result then
      Result := R;
  end;
end;

{ True if Name occurs anywhere in the content model. }
function SchemaContentMentions(const Content, Name: TLandrixXmlUtf8): Boolean;
var
  P, Start: Integer;
begin
  P := 1;
  while P <= Length(Content) do
  begin
    Start := P;
    while (P <= Length(Content)) and not (AnsiChar(Content[P]) in ['|', ';', '/', '?', '*', '+']) do
      Inc(P);
    if Copy(Content, Start, P - Start) = Name then
    begin
      Result := True;
      Exit;
    end;
    Inc(P);
  end;
  Result := False;
end;

function IsBlank(const S: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    if not (AnsiChar(S[I]) in [' ', #9, #10, #13]) then
    begin
      Result := False;
      Exit;
    end;
  Result := True;
end;

procedure TLoader.FailCheck(const FileName: string; Node: TLandrixXmlNode; const Code, Msg: string);
begin
  raise ELandrixXmlXsdSchemaError.CreateSchema(Code, 'XML Schema: ' + Msg + ' in ' + FileName, FileName,
    Node.Line, Node.Column);
end;

procedure TLoader.CheckSchemaNode(const FileName: string; Node: TLandrixXmlNode;
  const AKind: TLandrixXmlUtf8; Ids: TLandrixXmlXsdNameMap);
var
  Kind: TLandrixXmlUtf8;
  Rule: TSchemaRule;
  I, P, Count, Bad: Integer;
  Ns, Name, TypeName, Value, Item, Where: TLandrixXmlUtf8;
  Child: TLandrixXmlNode;
  Names: TLandrixXmlUtf8Array;
  Elements: array of TLandrixXmlNode;
begin
  { a reference: name, type, form and the like are not allowed (Xerces
    reports them as s4s-att-not-allowed) }
  Kind := AKind;
  if Node.AttributeIndex('', 'ref') >= 0 then
  begin
    if Kind = 'element.local' then
      Kind := 'element.ref'
    else if Kind = 'element.all' then
      Kind := 'element.allref'
    else if Kind = 'attribute.local' then
      Kind := 'attribute.ref';
  end;
  if not SchemaRuleOf(Kind, Rule) then
    Exit;
  Where := 'xs:' + Node.LocalNameUtf8;
  { the attributes and their values }
  for I := 0 to Node.AttributeCount - 1 do
  begin
    if Node.IsNamespaceDeclaration(I) then
      Continue;
    Ns := Node.AttributeNamespaceUriUtf8(I);
    Name := Node.AttributeLocalNameUtf8(I);
    if Ns = LandrixXmlXsdNamespace then
      FailCheck(FileName, Node, 's4s-att-not-allowed', 'the attribute "' + Esc(Node.AttributeNameUtf8(I)) +
        '" is not allowed in ' + Esc(Where));
    if (Ns = LandrixXmlNamespaceXml) and (Name = 'lang') and ((Kind = 'schema') or (Kind = 'documentation')) and
      not ValidBuiltin('language', Node.AttributeValueUtf8(I)) then
      FailCheck(FileName, Node, 's4s-att-invalid-value', 'the value "' + Esc(Node.AttributeValueUtf8(I)) +
        '" of the attribute "xml:lang" in ' + Esc(Where) + ' is not a valid language');
    if Ns <> '' then
      Continue;
    TypeName := SchemaAttributeType(Rule.Attributes, Name);
    if TypeName = '' then
      FailCheck(FileName, Node, 's4s-att-not-allowed', 'the attribute "' + Esc(Name) + '" is not allowed in ' +
        Esc(Where));
    Value := Node.AttributeValueUtf8(I);
    if not ValidSchemaValue(TypeName, Value) then
      FailCheck(FileName, Node, 's4s-att-invalid-value', 'the value "' + Esc(Value) + '" of the attribute "' +
        Esc(Name) + '" in ' + Esc(Where) + ' is not a valid ' + Esc(TypeName));
    if (TypeName = 'ID') and not Ids.Add('', LandrixXmlXsdNormalizeWhiteSpace(Value, xwsCollapse), Node) then
      FailCheck(FileName, Node, 's4s-att-invalid-value', 'the id "' + Esc(Value) + '" occurs twice in the document');
  end;
  { the required attributes }
  P := 1;
  while P <= Length(Rule.Attributes) do
  begin
    Item := NextToken(Rule.Attributes, P, ' ');
    if (Item <> '') and (Item[1] = '!') then
    begin
      Name := Copy(Item, 2, CharPos('=', Item) - 2);
      if Node.AttributeIndex('', Name) < 0 then
        FailCheck(FileName, Node, 's4s-att-must-appear', 'the attribute "' + Esc(Name) + '" must appear in ' +
          Esc(Where));
    end;
  end;
  if Rule.Content = '*' then
    Exit;
  { the children }
  Count := 0;
  Names := nil;
  Elements := nil;
  Child := Node.FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = xntElement then
    begin
      if Child.NamespaceUriUtf8 <> LandrixXmlXsdNamespace then
        FailCheck(FileName, Child, 's4s-elt-invalid-content.1', 'the element "' + Esc(Child.NameUtf8) +
          '" is not allowed in ' + Esc(Where));
      if Count = Length(Names) then
      begin
        SetLength(Names, 2 * Count + 8);
        SetLength(Elements, 2 * Count + 8);
      end;
      Names[Count] := Child.LocalNameUtf8;
      Elements[Count] := Child;
      Inc(Count);
    end
    else if ((Child.NodeType = xntText) or (Child.NodeType = xntCData)) and not IsBlank(Child.ValueUtf8) then
      FailCheck(FileName, Node, 's4s-elt-character', 'character data is not allowed in ' + Esc(Where));
    Child := Child.NextSibling;
  end;
  Bad := MatchSchemaContent(Rule.Content, Names, Count);
  if Bad >= Count then
    FailCheck(FileName, Node, 's4s-elt-must-match.1', 'the content of ' + Esc(Where) + ' is incomplete')
  else if Bad >= 0 then
  begin
    if SchemaContentMentions(Rule.Content, Names[Bad]) then
      FailCheck(FileName, Elements[Bad], 's4s-elt-must-match.1', 'xs:' + Esc(Names[Bad]) +
        ' is misplaced or occurs too often in ' + Esc(Where))
    else
      FailCheck(FileName, Elements[Bad], 's4s-elt-invalid-content.1', 'xs:' + Esc(Names[Bad]) +
        ' is not allowed in ' + Esc(Where));
  end;
  for I := 0 to Count - 1 do
    CheckSchemaNode(FileName, Elements[I], SchemaKindOf(Names[I], Kind), Ids);
end;

{ Once per file: a document included under several target namespaces is
  checked once. }
procedure TLoader.CheckSchemaDocument(const FileName: string; Root: TLandrixXmlNode);
var
  Ids: TLandrixXmlXsdNameMap;
begin
  if FCheckedFiles.IndexOf(FileIdentity(FileName)) >= 0 then
    Exit;
  FCheckedFiles.Add(FileIdentity(FileName));
  Ids := TLandrixXmlXsdNameMap.Create;
  try
    CheckSchemaNode(FileName, Root, 'schema', Ids);
  finally
    Ids.Free;
  end;
end;
