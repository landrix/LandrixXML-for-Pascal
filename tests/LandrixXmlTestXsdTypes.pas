{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for LandrixXmlXsdTypes: generated cases (tests/data/xsdtypes,
  results from the Xerces validator of the Java runtime), facet rules and
  white space handling. }

unit LandrixXmlTestXsdTypes;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  Classes,
  Contnrs,
  LandrixXmlBase,
  LandrixXmlXsdTypes,
  LandrixXmlTestFramework;

type
  TFields = array of string;

function U(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

function DataFile(const Name: string): string;
begin
  Result := IncludeTrailingPathDelimiter(RepositoryRoot) + 'tests' + PathDelim + 'data' +
    PathDelim + 'xsdtypes' + PathDelim + Name;
end;

function SplitTabs(const Line: string): TFields;
var
  P, N: Integer;
  Rest: string;
begin
  Result := nil;
  N := 0;
  Rest := Line;
  repeat
    P := Pos(#9, Rest);
    SetLength(Result, N + 1);
    if P = 0 then
      Result[N] := Rest
    else
    begin
      Result[N] := Copy(Rest, 1, P - 1);
      Rest := Copy(Rest, P + 1, MaxInt);
    end;
    Inc(N);
  until P = 0;
end;

function HexValue(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := 0;
    Fail('bad hex digit');
  end;
end;

function Decode(const F: string): TLandrixXmlUtf8;
var
  I: Integer;
begin
  if Copy(F, 1, 4) <> 'hex:' then
  begin
    Result := U(F);
    Exit;
  end;
  Result := '';
  SetLength(Result, (Length(F) - 4) div 2);
  for I := 1 to Length(Result) do
    Result[I] := AnsiChar(HexValue(F[3 + 2 * I]) * 16 + HexValue(F[4 + 2 * I]));
end;

function FacetOf(const Name: string): TLandrixXmlXsdFacet;
begin
  if Name = 'length' then Result := xsfLength
  else if Name = 'minLength' then Result := xsfMinLength
  else if Name = 'maxLength' then Result := xsfMaxLength
  else if Name = 'pattern' then Result := xsfPattern
  else if Name = 'enumeration' then Result := xsfEnumeration
  else if Name = 'whiteSpace' then Result := xsfWhiteSpace
  else if Name = 'maxInclusive' then Result := xsfMaxInclusive
  else if Name = 'maxExclusive' then Result := xsfMaxExclusive
  else if Name = 'minInclusive' then Result := xsfMinInclusive
  else if Name = 'minExclusive' then Result := xsfMinExclusive
  else if Name = 'totalDigits' then Result := xsfTotalDigits
  else if Name = 'fractionDigits' then Result := xsfFractionDigits
  else
  begin
    Result := xsfLength;
    Fail('unknown facet ' + Name);
  end;
end;

{ Types of types.txt by id; Owned keeps the derived ones. }
function FindType(Names: TStrings; const Id: string): TLandrixXmlXsdSimpleType;
var
  I: Integer;
begin
  I := Names.IndexOf(Id);
  if I >= 0 then
    Result := TLandrixXmlXsdSimpleType(Names.Objects[I])
  else
    Result := LandrixXmlXsdBuiltinType(U(Id));
  if Result = nil then
    Fail('unknown type ' + Id);
end;

procedure LoadTypes(Names: TStrings; Owned: TObjectList);
var
  L: TStringList;
  K, I, P: Integer;
  Fields: TFields;
  T: TLandrixXmlXsdSimpleType;
  Members: array of TLandrixXmlXsdSimpleType;
begin
  Fields := nil;
  Members := nil;
  L := TStringList.Create;
  try
    L.LoadFromFile(DataFile('types.txt'));
    for K := 0 to L.Count - 1 do
    begin
      Fields := SplitTabs(L[K]);
      if Fields[1] = 'union' then
      begin
        SetLength(Members, Length(Fields) - 2);
        for I := 2 to Integer(Length(Fields)) - 1 do
          Members[I - 2] := FindType(Names, Fields[I]);
        T := TLandrixXmlXsdSimpleType.CreateUnion(Members, '', U(Fields[0]));
      end
      else
      begin
        T := TLandrixXmlXsdSimpleType.CreateRestriction(FindType(Names, Fields[1]), '', U(Fields[0]));
        Owned.Add(T);
        for I := 2 to Integer(Length(Fields)) - 1 do
        begin
          P := Pos('=', Fields[I]);
          T.AddFacet(FacetOf(Copy(Fields[I], 1, P - 1)), Decode(Copy(Fields[I], P + 1, MaxInt)));
        end;
        Names.AddObject(Fields[0], T);
        Continue;
      end;
      Owned.Add(T);
      Names.AddObject(Fields[0], T);
    end;
  finally
    L.Free;
  end;
end;

procedure TestGeneratedData;
var
  Names, L: TStringList;
  Owned: TObjectList;
  K: Integer;
  Fields: TFields;
  Value: TLandrixXmlXsdValue;
  Error: TLandrixXmlXsdError;
  Got, Mismatches: string;
  MismatchCount: Integer;
begin
  Fields := nil;
  Mismatches := '';
  MismatchCount := 0;
  Names := TStringList.Create;
  Owned := TObjectList.Create(True);
  L := TStringList.Create;
  try
    LoadTypes(Names, Owned);
    L.LoadFromFile(DataFile('cases.txt'));
    Check(L.Count > 1500, 'type cases present');
    for K := 0 to L.Count - 1 do
    begin
      Fields := SplitTabs(L[K]);
      if FindType(Names, Fields[0]).Validate(Decode(Fields[1]), Value, Error) then
        Got := ''
      else
        Got := Error.Code;
      { all differences are collected: they usually share one cause }
      if Got <> Fields[2] then
      begin
        Inc(MismatchCount);
        if MismatchCount <= 25 then
          Mismatches := Mismatches + #10 + '  line ' + IntToStr(K + 1) + ': ' + L[K] + ' -> got "' +
            Got + '" (' + Error.Message + ')';
      end;
    end;
    Check(MismatchCount = 0, IntToStr(MismatchCount) + ' differences from Xerces:' + Mismatches);
  finally
    L.Free;
    Owned.Free;
    Names.Free;
  end;
end;

procedure TestWhiteSpace;
begin
  CheckEqualsUtf8(U('a b c'), LandrixXmlXsdNormalizeWhiteSpace(U(#9' a'#13#10'  b  c '), xwsCollapse),
    'collapse');
  CheckEqualsUtf8(U('  a  b '), LandrixXmlXsdNormalizeWhiteSpace(U(#9' a'#10' b'#13), xwsReplace), 'replace');
  CheckEqualsUtf8(U(#9'a'), LandrixXmlXsdNormalizeWhiteSpace(U(#9'a'), xwsPreserve), 'preserve');
  CheckEqualsUtf8(U(''), LandrixXmlXsdNormalizeWhiteSpace(U('   '), xwsCollapse), 'only spaces');
end;

procedure CheckFacetError(Base: TLandrixXmlXsdSimpleType; Facet: TLandrixXmlXsdFacet;
  const Value: string; Code: TLandrixXmlErrorCode; const Name: string);
var
  T: TLandrixXmlXsdSimpleType;
begin
  T := TLandrixXmlXsdSimpleType.CreateRestriction(Base, '', U('t'));
  try
    try
      T.AddFacet(Facet, U(Value));
      FailNotRaised('ELandrixXmlError for ' + Name);
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(Code), Ord(E.Code), Name + ': ' + E.Message);
    end;
  finally
    T.Free;
  end;
end;

procedure TestFacetRules;
var
  Str, Bool, Dec: TLandrixXmlXsdSimpleType;
begin
  Str := LandrixXmlXsdBuiltinType('token');
  Bool := LandrixXmlXsdBuiltinType('boolean');
  Dec := LandrixXmlXsdBuiltinType('decimal');
  Check(Str <> nil, 'token known');
  Check(LandrixXmlXsdBuiltinType('duration') <> nil, 'duration known');
  Check(LandrixXmlXsdBuiltinType('ENTITY') <> nil, 'ENTITY known');
  Check(LandrixXmlXsdBuiltinType('ENTITIES') <> nil, 'ENTITIES known');
  Check(LandrixXmlXsdBuiltinType('error') = nil, 'xs:error unknown');
  Check(LandrixXmlXsdBuiltinType('NOTATION') <> nil, 'NOTATION known');
  CheckFacetError(Bool, xsfEnumeration, 'true', xecInvalidArgument, 'enumeration on boolean');
  CheckFacetError(Str, xsfTotalDigits, '3', xecInvalidArgument, 'totalDigits on a string');
  CheckFacetError(Dec, xsfMaxLength, '3', xecInvalidArgument, 'maxLength on a decimal');
  CheckFacetError(Dec, xsfMaxInclusive, 'abc', xecInvalidArgument, 'invalid bound');
  CheckFacetError(Str, xsfMaxLength, '-1', xecInvalidArgument, 'negative length');
  CheckFacetError(Str, xsfWhiteSpace, 'preserve', xecInvalidArgument, 'weaker whiteSpace');
  CheckFacetError(Str, xsfPattern, '[a', xecRegex, 'invalid pattern');
  CheckFacetError(LandrixXmlXsdBuiltinType('anySimpleType'), xsfMinLength, '1', xecInvalidArgument,
    'a facet on anySimpleType');
end;

{ Facets as "name=value" ("!" before the name for a fixed facet),
  separated by ";". }
procedure AddFacetList(Target: TLandrixXmlXsdSimpleType; const List: string);
var
  Fields: TStringList;
  I, P: Integer;
  Field: string;
  Fixed: Boolean;
begin
  Fields := TStringList.Create;
  try
    Fields.Text := StringReplace(List, ';', #10, [rfReplaceAll]);
    for I := 0 to Integer(Fields.Count) - 1 do
    begin
      Field := Fields[I];
      Fixed := (Field <> '') and (Field[1] = '!');
      if Fixed then
        Delete(Field, 1, 1);
      P := Pos('=', Field);
      Target.AddFacet(FacetOf(Copy(Field, 1, P - 1)), U(Copy(Field, P + 1, MaxInt)), Fixed);
    end;
  finally
    Fields.Free;
  end;
end;

{ A chain of restrictions of the built-in BaseName, one for each part of
  BaseFacets separated by "|" (see AddFacetList), then a restriction with
  Facets; Code is the constraint code expected for the last facet of
  Facets, '' if all facets are accepted. }
procedure CheckConsistency(const BaseName, BaseFacets, Facets, Code, Name: string);
var
  Types: TObjectList;
  Base, T: TLandrixXmlXsdSimpleType;
  Rest, Last: string;
  P: Integer;
begin
  Types := TObjectList.Create(True);
  try
    Base := LandrixXmlXsdBuiltinType(U(BaseName));
    Rest := BaseFacets + '|';
    while Rest <> '' do
    begin
      P := Pos('|', Rest);
      T := TLandrixXmlXsdSimpleType.CreateRestriction(Base, '', U('b'));
      Types.Add(T);
      AddFacetList(T, Copy(Rest, 1, P - 1));
      Delete(Rest, 1, P);
      Base := T;
    end;
    T := TLandrixXmlXsdSimpleType.CreateRestriction(Base, '', U('t'));
    Types.Add(T);
    { the facets before the last one must be accepted }
    Last := Facets;
    P := Pos(';', Last);
    while P > 0 do
    begin
      AddFacetList(T, Copy(Last, 1, P - 1));
      Delete(Last, 1, P);
      P := Pos(';', Last);
    end;
    try
      AddFacetList(T, Last);
      CheckEqualsStr(Code, '', Name);
    except
      on E: ELandrixXmlError do
      begin
        CheckEquals(Ord(xecInvalidArgument), Ord(E.Code), Name + ': ' + E.Message);
        Check((Code <> '') and (Copy(E.Message, Integer(Length(E.Message)) - Integer(Length(Code)) - 1, MaxInt) =
          '(' + Code + ')'), Name + ': ' + E.Message);
      end;
    end;
  finally
    Types.Free;
  end;
end;

procedure TestFacetConsistency;
begin
  CheckConsistency('string', '', 'minLength=3;maxLength=2', 'minLength-less-than-equal-to-maxLength',
    'minLength above maxLength');
  CheckConsistency('string', 'maxLength=5', 'maxLength=6', 'maxLength-valid-restriction', 'wider maxLength');
  CheckConsistency('string', 'maxLength=5', 'minLength=6', 'minLength-less-than-equal-to-maxLength',
    'minLength above the base maxLength');
  CheckConsistency('string', 'minLength=2', 'minLength=1', 'minLength-valid-restriction', 'smaller minLength');
  CheckConsistency('string', '!minLength=2', 'minLength=3', 'FixedFacetValue', 'fixed minLength');
  CheckConsistency('string', 'minLength=2', 'length=3;minLength=2', '', 'length with the base minLength');
  CheckConsistency('string', '', 'length=3;maxLength=4', 'length-minLength-maxLength.2.2.a',
    'maxLength beside length');
  CheckConsistency('string', 'length=3', 'length=4', 'length-valid-restriction', 'other length');
  CheckConsistency('string', 'maxLength=2', 'length=3', 'length-minLength-maxLength.2.1',
    'length above the base maxLength');
  CheckConsistency('string', '', 'minLength=2;minLength=3', 'src-single-facet-value', 'minLength twice');
  CheckConsistency('decimal', '', 'minInclusive=5;maxInclusive=4', 'minInclusive-less-than-equal-to-maxInclusive',
    'empty inclusive range');
  CheckConsistency('decimal', '', 'minInclusive=4;maxInclusive=4', '', 'one value');
  CheckConsistency('decimal', '', 'maxExclusive=4;minInclusive=4', 'minInclusive-less-than-maxExclusive',
    'minInclusive at maxExclusive');
  CheckConsistency('decimal', '', 'maxInclusive=4;minExclusive=4', 'minExclusive-less-than-maxInclusive',
    'minExclusive at maxInclusive');
  CheckConsistency('decimal', '', 'minExclusive=5;maxExclusive=4',
    'minExclusive-less-than-equal-to-maxExclusive', 'empty exclusive range');
  CheckConsistency('decimal', '', 'maxInclusive=4;maxExclusive=5', 'maxInclusive-maxExclusive',
    'both upper bounds');
  CheckConsistency('decimal', '', 'minInclusive=4;minExclusive=3', 'minInclusive-minExclusive',
    'both lower bounds');
  CheckConsistency('decimal', 'maxInclusive=10', 'maxInclusive=11', 'cvc-maxInclusive-valid',
    'bound outside the base type');
  CheckConsistency('decimal', 'maxExclusive=10', 'maxExclusive=10', '', 'the base maxExclusive repeated');
  CheckConsistency('decimal', 'minExclusive=1', 'minExclusive=1', '', 'the base minExclusive repeated');
  CheckConsistency('decimal', '!maxInclusive=10', 'maxInclusive=9', 'FixedFacetValue', 'fixed maxInclusive');
  CheckConsistency('decimal', '!maxInclusive=10', 'maxInclusive=10.0', '', 'fixed maxInclusive repeated');
  CheckConsistency('decimal', '!maxInclusive=10', 'maxInclusive=11', 'FixedFacetValue',
    'fixed maxInclusive before the base bound');
  CheckConsistency('decimal', 'pattern=[0-9]+;maxExclusive=10', 'maxExclusive=10.0', 'cvc-pattern-valid',
    'repeated maxExclusive against the base pattern');
  CheckConsistency('decimal', '', 'totalDigits=2;fractionDigits=3', 'fractionDigits-totalDigits',
    'fractionDigits above totalDigits');
  CheckConsistency('decimal', 'totalDigits=4', 'totalDigits=5', 'totalDigits-valid-restriction',
    'wider totalDigits');
  CheckConsistency('decimal', 'fractionDigits=2', 'fractionDigits=3', 'fractionDigits-valid-restriction',
    'wider fractionDigits');
  CheckConsistency('decimal', '!totalDigits=4', 'totalDigits=3', 'FixedFacetValue', 'fixed totalDigits');
  CheckConsistency('integer', '', 'fractionDigits=1', 'FixedFacetValue', 'fractionDigits on an integer');
  CheckConsistency('integer', '', 'fractionDigits=0', '', 'fractionDigits 0 on an integer');
  CheckConsistency('string', '!whiteSpace=replace', 'whiteSpace=collapse', 'FixedFacetValue', 'fixed whiteSpace');
  CheckConsistency('string', 'whiteSpace=replace', 'whiteSpace=preserve', 'whiteSpace-valid-restriction.2',
    'whiteSpace preserve after replace');
  CheckConsistency('string', '', 'enumeration=a;enumeration=b', '', 'enumerations');
  CheckConsistency('string', '!maxLength=5|maxLength=5', 'maxLength=4', 'FixedFacetValue',
    'fixed maxLength inherited');
  CheckConsistency('decimal', '!maxInclusive=10|maxExclusive=9', 'maxInclusive=5', '',
    'a fixed maxInclusive hidden by a maxExclusive');
  CheckConsistency('decimal', '!minInclusive=1|minExclusive=2', 'minInclusive=5', '',
    'a fixed minInclusive hidden by a minExclusive');
  CheckConsistency('decimal', 'maxExclusive=10|totalDigits=5', 'maxExclusive=10', '',
    'an inherited maxExclusive repeated');
  CheckConsistency('decimal', '!maxExclusive=10', 'maxExclusive=9', 'FixedFacetValue', 'fixed maxExclusive');
  CheckConsistency('decimal', 'totalDigits=3', 'fractionDigits=4', 'fractionDigits-totalDigits',
    'fractionDigits above the base totalDigits');
  CheckConsistency('decimal', '', 'whiteSpace=replace', 'FixedFacetValue', 'whiteSpace on a decimal');
  CheckConsistency('string', 'whiteSpace=collapse', 'whiteSpace=replace', 'whiteSpace-valid-restriction.1',
    'whiteSpace replace after collapse');
  CheckConsistency('NMTOKENS', '', 'length=3', '', 'length of a list');
  CheckConsistency('string', 'length=3', 'length=3', '', 'the base length repeated');
  CheckConsistency('string', 'maxLength=3', 'maxLength=3', '', 'the base maxLength repeated');
  CheckConsistency('decimal', 'totalDigits=3', 'totalDigits=3', '', 'the base totalDigits repeated');
  CheckConsistency('string', 'length=3', 'minLength=3', 'length-minLength-maxLength.1.2.a',
    'minLength after a base length');
  CheckConsistency('string', '!whiteSpace=replace|minLength=1', 'whiteSpace=collapse', 'FixedFacetValue',
    'fixed whiteSpace inherited');
  CheckConsistency('double', '', 'minInclusive=NaN;maxInclusive=NaN', '', 'NaN bounds');
  CheckConsistency('date', '', 'minInclusive=2000-01-01;maxInclusive=2000-01-01Z',
    'minInclusive-less-than-equal-to-maxInclusive', 'indeterminate date bounds');
  CheckConsistency('NMTOKENS', 'maxLength=2', 'length=3', 'length-minLength-maxLength.2.1',
    'length of a list above the base maxLength');
end;

type
  { p and x bound to urn:p, the default namespace to urn:d }
  TTestContext = class(TLandrixXmlXsdNamespaceContext)
  public
    function LookupNamespace(const Prefix: TLandrixXmlUtf8; out NamespaceUri: TLandrixXmlUtf8): Boolean;
      override;
  end;

function TTestContext.LookupNamespace(const Prefix: TLandrixXmlUtf8; out NamespaceUri: TLandrixXmlUtf8): Boolean;
begin
  Result := True;
  if (Prefix = 'p') or (Prefix = 'x') then
    NamespaceUri := 'urn:p'
  else if Prefix = '' then
    NamespaceUri := 'urn:d'
  else
  begin
    NamespaceUri := '';
    Result := False;
  end;
end;

procedure TestQName;
var
  QN, R: TLandrixXmlXsdSimpleType;
  Context: TTestContext;
  V, W: TLandrixXmlXsdValue;
  Error: TLandrixXmlXsdError;
begin
  QN := LandrixXmlXsdBuiltinType('QName');
  Check(QN <> nil, 'QName known');
  Context := TTestContext.Create;
  R := TLandrixXmlXsdSimpleType.CreateRestriction(QN, '', U('r'));
  try
    Check(QN.Validate(U(' p:a '), Context, V, Error), 'prefixed QName');
    CheckEqualsUtf8(U('urn:p'), V.NamespaceUri, 'namespace of p:a');
    CheckEqualsUtf8(U('a'), V.LocalName, 'local name of p:a');
    CheckEqualsUtf8(U('p:a'), LandrixXmlXsdValueText(V), 'text of p:a');
    Check(QN.Validate(U('a'), Context, W, Error), 'QName without prefix');
    CheckEqualsUtf8(U('urn:d'), W.NamespaceUri, 'default namespace');
    Check(LandrixXmlXsdCompareValues(V, W) = LandrixXmlXsdIncomparable, 'p:a and a differ');
    Check(QN.Validate(U('x:a'), Context, W, Error), 'other prefix');
    CheckEquals(0, LandrixXmlXsdCompareValues(V, W), 'p:a equals x:a');
    CheckEqualsUtf8(LandrixXmlXsdValueKey(V), LandrixXmlXsdValueKey(W), 'same key for p:a and x:a');
    Check(not QN.Validate(U('q:a'), Context, W, Error), 'undeclared prefix');
    CheckEqualsStr('UndeclaredPrefix', Error.Code, 'code of an undeclared prefix');
    Check(not QN.Validate(U('p:a'), W, Error), 'no context');
    CheckEqualsStr('UndeclaredPrefix', Error.Code, 'code without context');
    Check(QN.Validate(U('a'), W, Error) and (W.NamespaceUri = ''), 'no prefix, no context');
    Check(not QN.Validate(U('p:1a'), Context, W, Error), 'local part not an NCName');
    CheckEqualsStr('cvc-datatype-valid.1.2.1', Error.Code, 'code of an invalid QName');
    Check(not QN.Validate(U(':a'), Context, W, Error), 'empty prefix');
    { the enumeration resolves in its own context; length does not count }
    R.AddFacet(xsfEnumeration, U('x:a'), Context, False);
    R.AddFacet(xsfLength, U('1'));
    Check(R.Validate(U('p:a'), Context, W, Error), 'enumeration by expanded name');
    Check(not R.Validate(U('a'), Context, W, Error), 'other namespace not in the enumeration');
    CheckEqualsStr('cvc-enumeration-valid', Error.Code, 'code of the enumeration');
  finally
    R.Free;
    Context.Free;
  end;
end;

{ DerivationOk and Final of simple types }
procedure TestSimpleDerivation;
var
  Dec, Int, Bool, Str, AnySimple: TLandrixXmlXsdSimpleType;
  D, U2, L, X: TLandrixXmlXsdSimpleType;
begin
  Dec := LandrixXmlXsdBuiltinType('decimal');
  Int := LandrixXmlXsdBuiltinType('int');
  Bool := LandrixXmlXsdBuiltinType('boolean');
  Str := LandrixXmlXsdBuiltinType('string');
  AnySimple := LandrixXmlXsdBuiltinType('anySimpleType');
  Check(Int.DerivationOk(Int, [xdRestriction]), 'a type from itself');
  Check(Int.DerivationOk(Dec, []), 'int from decimal');
  Check(not Int.DerivationOk(Dec, [xdRestriction]), 'restriction blocked');
  Check(not Dec.DerivationOk(Int, []), 'decimal from int');
  Check(not Str.DerivationOk(Dec, []), 'string from decimal');
  Check(Int.Final = [], 'no final on a built-in type');
  try
    Int.Final := [xdRestriction];
    FailNotRaised('ELandrixXmlError for the final of a built-in type');
  except
    on E: ELandrixXmlError do
      CheckEquals(Ord(xecInvalidOperation), Ord(E.Code), 'final of a built-in type');
  end;
  D := TLandrixXmlXsdSimpleType.CreateRestriction(Int, '', U('d'));
  U2 := TLandrixXmlXsdSimpleType.CreateUnion([Bool, Dec], '', U('u'));
  L := TLandrixXmlXsdSimpleType.CreateList('', U('l'), Int);
  try
    Check(D.DerivationOk(Dec, []), 'through two restrictions');
    Check(D.DerivationOk(U2, []), 'through a member of a union');
    Check(not Str.DerivationOk(U2, []), 'string is no member of the union');
    Check(L.DerivationOk(AnySimple, []), 'a list from anySimpleType');
    Check(not L.DerivationOk(Int, []), 'a list from its item type');
    D.Final := [xdRestriction];
    Check(D.Final = [xdRestriction], 'final set');
    X := TLandrixXmlXsdSimpleType.CreateRestriction(D, '', U('x'));
    try
      Check(not X.DerivationOk(Int, []), 'the final of the base forbids the restriction');
      Check(not X.DerivationOk(D, []), 'not even from the base itself (Xerces 2.1 first)');
    finally
      X.Free;
    end;
  finally
    L.Free;
    U2.Free;
    D.Free;
  end;
end;

procedure TestUnionFacets;
var
  U1, R: TLandrixXmlXsdSimpleType;
begin
  R := nil;
  U1 := TLandrixXmlXsdSimpleType.CreateUnion([LandrixXmlXsdBuiltinType('int'),
    LandrixXmlXsdBuiltinType('date')], '', U('u'));
  try
    { the facets of a union go on a restriction of it }
    try
      U1.AddFacet(xsfPattern, U('[0-9]+'));
      FailNotRaised('ELandrixXmlError for a facet on a union');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidOperation), Ord(E.Code), 'facet on a union');
    end;
    { only pattern and enumeration apply to a union }
    R := TLandrixXmlXsdSimpleType.CreateRestriction(U1, '', U('r'));
    try
      R.AddFacet(xsfWhiteSpace, U('collapse'));
      FailNotRaised('ELandrixXmlError for whiteSpace on a union');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidArgument), Ord(E.Code), 'whiteSpace on a union');
    end;
    R.AddFacet(xsfPattern, U('[0-9]+'));
  finally
    R.Free;
    U1.Free;
  end;
end;

function Val(const TypeName, Text: string): TLandrixXmlXsdValue;
var
  Error: TLandrixXmlXsdError;
begin
  if not LandrixXmlXsdBuiltinType(U(TypeName)).Validate(U(Text), Result, Error) then
    Fail(Text + ' should be a valid ' + TypeName + ': ' + Error.Message);
end;

procedure TestCompareValues;
begin
  CheckEquals(0, LandrixXmlXsdCompareValues(Val('decimal', '1.50'), Val('decimal', '1.5')), '1.50 = 1.5');
  CheckEquals(LandrixXmlXsdIncomparable, LandrixXmlXsdCompareValues(Val('decimal', '1'), Val('string', '1')),
    'different primitives');
  CheckEquals(0, LandrixXmlXsdCompareValues(Val('double', 'NaN'), Val('double', 'NaN')), 'NaN = NaN');
  CheckEquals(0, LandrixXmlXsdCompareValues(Val('hexBinary', '0a'), Val('hexBinary', '0A')), 'hex case');
  CheckEquals(0, LandrixXmlXsdCompareValues(Val('base64Binary', 'QUJD'), Val('base64Binary', 'Q U J D')),
    'base64 spaces');
  { +-14 hours: 02:00:00Z lies before 16:00:30 without time zone in any zone }
  CheckEquals(-1, LandrixXmlXsdCompareValues(Val('time', '02:00:00Z'), Val('time', '16:00:30')), '14h rule');
  CheckEquals(LandrixXmlXsdIncomparable, LandrixXmlXsdCompareValues(Val('time', '02:00:31Z'),
    Val('time', '16:00:30')), '14h rule, within the window');
  CheckEquals(-1, LandrixXmlXsdCompareValues(Val('date', '-0001-12-31'), Val('date', '0001-01-01')),
    'year -1 before year 1');
  CheckEquals(-1, LandrixXmlXsdCompareValues(Val('date', '-0001-02-28'), Val('date', '-0001-03-01')),
    'negative year, consecutive days');
end;

procedure TestValueFields;
var
  U1: TLandrixXmlXsdSimpleType;
  V: TLandrixXmlXsdValue;
  Error: TLandrixXmlXsdError;
begin
  U1 := TLandrixXmlXsdSimpleType.CreateUnion([LandrixXmlXsdBuiltinType('int'),
    LandrixXmlXsdBuiltinType('date')], '', U('u'));
  try
    Check(U1.Validate(U(' 2026-10-21 '), V, Error), 'union value');
    Check(V.MemberType = LandrixXmlXsdBuiltinType('date'), 'member type');
    CheckEqualsUtf8(U(' 2026-10-21 '), V.RawText, 'raw text');
    CheckEqualsUtf8(U('2026-10-21'), V.Text, 'normalized text');
  finally
    U1.Free;
  end;
end;

{ list types: items, their member types, length facets, comparison, keys }
procedure TestLists;
var
  L, L2, L3, R, UL: TLandrixXmlXsdSimpleType;
  V, W: TLandrixXmlXsdValue;
  Error: TLandrixXmlXsdError;
begin
  L := TLandrixXmlXsdSimpleType.CreateList('', U('decs'), LandrixXmlXsdBuiltinType('decimal'));
  R := nil;
  UL := nil;
  try
    Check(L.Variety = xsvList, 'variety');
    Check(L.ItemType = LandrixXmlXsdBuiltinType('decimal'), 'item type');
    Check(L.Validate(U(' 1.50  2 '), V, Error), 'a list of decimals');
    Check(V.Variety = xsvList, 'list value');
    CheckEquals(2, V.Length, 'length = items');
    CheckEquals(2, Integer(Length(V.Items)), 'two items');
    CheckEqualsUtf8(U('1.50 2'), V.Text, 'collapsed text');
    Check(V.Items[0].MemberType = LandrixXmlXsdBuiltinType('decimal'), 'item member type');
    CheckEqualsUtf8(U('1.5 2.0'), LandrixXmlXsdValueText(V), 'canonical text');
    Check(L.Validate(U('1.5 2.0'), W, Error), 'the same list');
    CheckEquals(0, LandrixXmlXsdCompareValues(V, W), 'equal lists');
    CheckEqualsUtf8(LandrixXmlXsdValueKey(V), LandrixXmlXsdValueKey(W), 'equal keys');
    Check(L.Validate(U('1.5'), W, Error), 'one item');
    CheckEquals(LandrixXmlXsdIncomparable, LandrixXmlXsdCompareValues(V, W), 'different lengths');
    Check(LandrixXmlXsdValueKey(W) <> LandrixXmlXsdValueKey(Val('decimal', '1.5')), 'a list key is not an item key');
    Check(L.Validate(U(''), W, Error), 'an empty list');
    CheckEquals(0, W.Length, 'no items');
    Check(not L.Validate(U('1 x'), W, Error), 'a bad item');
    CheckEqualsStr('cvc-datatype-valid.1.2.1', Error.Code, 'the item''s error');
    try
      L.AddFacet(xsfEnumeration, U('1 2'));
      FailNotRaised('ELandrixXmlError for a facet on the list type itself');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidOperation), Ord(E.Code), 'a facet on the list type itself');
    end;
    R := TLandrixXmlXsdSimpleType.CreateRestriction(L, '', U('two'));
    R.AddFacet(xsfLength, U('2'));
    Check(R.ItemType = L.ItemType, 'a restriction keeps the item type');
    Check(not R.Validate(U('1'), W, Error), 'length 2');
    CheckEqualsStr('cvc-length-valid', Error.Code, 'length facet');
    try
      R.AddFacet(xsfMaxInclusive, U('3'));
      FailNotRaised('ELandrixXmlError for maxInclusive on a list');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidArgument), Ord(E.Code), 'maxInclusive on a list');
    end;
    { anySimpleType and string items compare as strings, as in Xerces }
    L2 := TLandrixXmlXsdSimpleType.CreateList('', U('any'), LandrixXmlXsdBuiltinType('anySimpleType'));
    L3 := TLandrixXmlXsdSimpleType.CreateList('', U('str'), LandrixXmlXsdBuiltinType('string'));
    try
      Check(L2.Validate(U('a b'), V, Error), 'a list of anySimpleType');
      Check(L3.Validate(U('a b'), W, Error), 'a list of string');
      CheckEquals(0, LandrixXmlXsdCompareValues(V, W), 'anySimpleType and string lists');
    finally
      L3.Free;
      L2.Free;
    end;
    CheckEquals(0, LandrixXmlXsdCompareValues(Val('anySimpleType', 'a'), Val('string', 'a')),
      'anySimpleType and string values');
    Check(LandrixXmlXsdBuiltinType('NMTOKENS').Variety = xsvList, 'NMTOKENS');
    Check(not LandrixXmlXsdBuiltinType('IDREFS').Validate(U(' '), W, Error), 'IDREFS needs an item');
    CheckEqualsStr('cvc-minLength-valid', Error.Code, 'IDREFS minLength');
    Check(not LandrixXmlXsdBuiltinType('ENTITIES').Validate(U(' '), W, Error), 'ENTITIES needs an item');
    Check(LandrixXmlXsdBuiltinType('ENTITIES').Validate(U('a b'), W, Error), 'ENTITIES of NCNames');
    { a list of lists, or of a union with a list member }
    UL := TLandrixXmlXsdSimpleType.CreateUnion([LandrixXmlXsdBuiltinType('int'), L], '', U('ul'));
    try
      L2 := TLandrixXmlXsdSimpleType.CreateList('', U('bad'), UL);
      L2.Free;
      FailNotRaised('ELandrixXmlError for a list of a union with a list');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidArgument), Ord(E.Code), 'list of a union with a list');
    end;
    Check(UL.Validate(U('1 2'), W, Error), 'a union with a list member');
    Check(W.MemberType = L, 'the list member');
    Check(W.Variety = xsvList, 'a list value');
  finally
    UL.Free;
    R.Free;
    L.Free;
  end;
end;

{ HasValue: the value Xerces has computed when a later check fails }
procedure TestHasValue;
var
  Small, Code, Color, L, R, U1, U2: TLandrixXmlXsdSimpleType;
  V: TLandrixXmlXsdValue;
  Error: TLandrixXmlXsdError;
  HasValue: Boolean;
begin
  Small := TLandrixXmlXsdSimpleType.CreateRestriction(LandrixXmlXsdBuiltinType('int'), '', U('small'));
  Code := nil;
  Color := nil;
  L := nil;
  R := nil;
  U1 := nil;
  U2 := nil;
  try
    Small.AddFacet(xsfMaxInclusive, U('100'));
    Check(Small.Validate(U('5'), nil, V, Error, HasValue), 'a valid value');
    Check(HasValue, 'a valid value has its value');
    Check(not Small.Validate(U('150'), nil, V, Error, HasValue), 'maxInclusive');
    CheckEqualsStr('cvc-maxInclusive-valid', Error.Code, 'the facet''s error');
    Check(HasValue, 'a facet failure keeps the value');
    CheckEqualsUtf8(U('150'), LandrixXmlXsdValueText(V), 'the value');
    Check(not Small.Validate(U('x'), nil, V, Error, HasValue), 'not an int');
    Check(not HasValue, 'a lexical failure has no value');
    Code := TLandrixXmlXsdSimpleType.CreateRestriction(LandrixXmlXsdBuiltinType('string'), '', U('code'));
    Code.AddFacet(xsfPattern, U('[A-Z]+'));
    Code.AddFacet(xsfLength, U('3'));
    Check(not Code.Validate(U('abc'), nil, V, Error, HasValue), 'pattern');
    Check(not HasValue, 'a pattern failure has no value');
    Check(not Code.Validate(U('ABCD'), nil, V, Error, HasValue), 'length');
    Check(HasValue, 'a length failure keeps the value');
    { lists: the whole list, else the last item that had a value }
    L := TLandrixXmlXsdSimpleType.CreateList('', U('l'), Small);
    R := TLandrixXmlXsdSimpleType.CreateRestriction(L, '', U('pair'));
    R.AddFacet(xsfLength, U('2'));
    Check(not R.Validate(U('1 2 3'), nil, V, Error, HasValue), 'list length');
    Check(HasValue and (V.Variety = xsvList) and (V.Length = 3), 'the list value');
    Check(not R.Validate(U('1 200'), nil, V, Error, HasValue), 'an item over maxInclusive');
    Check(HasValue and (V.Variety = xsvAtomic), 'the item''s value');
    CheckEqualsUtf8(U('200'), LandrixXmlXsdValueText(V), 'the failed item');
    Check(not R.Validate(U('1 x'), nil, V, Error, HasValue), 'an item that is no int');
    Check(HasValue, 'the item before');
    CheckEqualsUtf8(U('1'), LandrixXmlXsdValueText(V), 'the last item with a value');
    Check(not R.Validate(U('x 1'), nil, V, Error, HasValue), 'the first item is no int');
    Check(not HasValue, 'no item had a value');
    { unions: the last member type that had a value }
    Color := TLandrixXmlXsdSimpleType.CreateRestriction(LandrixXmlXsdBuiltinType('string'), '', U('color'));
    Color.AddFacet(xsfEnumeration, U('red'));
    U1 := TLandrixXmlXsdSimpleType.CreateUnion([Small, Color], '', U('u1'));
    Check(not U1.Validate(U('200'), nil, V, Error, HasValue), 'no member matches');
    CheckEqualsStr('cvc-datatype-valid.1.2.3', Error.Code, 'the union''s error');
    Check(HasValue and (V.MemberType = Color), 'the value of the last member');
    U2 := TLandrixXmlXsdSimpleType.CreateUnion([LandrixXmlXsdBuiltinType('boolean'), Small], '', U('u2'));
    Check(not U2.Validate(U('200'), nil, V, Error, HasValue), 'no member matches either');
    Check(HasValue and (V.MemberType = Small), 'the only member with a value');
    Check(not U2.Validate(U('x'), nil, V, Error, HasValue), 'no member has a value');
    Check(not HasValue, 'no value');
  finally
    U2.Free;
    U1.Free;
    Color.Free;
    R.Free;
    L.Free;
    Code.Free;
    Small.Free;
  end;
end;

procedure Register;
begin
  RegisterTest('XsdTypes.GeneratedData', TestGeneratedData);
  RegisterTest('XsdTypes.WhiteSpace', TestWhiteSpace);
  RegisterTest('XsdTypes.FacetRules', TestFacetRules);
  RegisterTest('XsdTypes.FacetConsistency', TestFacetConsistency);
  RegisterTest('XsdTypes.UnionFacets', TestUnionFacets);
  RegisterTest('XsdTypes.QName', TestQName);
  RegisterTest('XsdTypes.SimpleDerivation', TestSimpleDerivation);
  RegisterTest('XsdTypes.CompareValues', TestCompareValues);
  RegisterTest('XsdTypes.ValueFields', TestValueFields);
  RegisterTest('XsdTypes.Lists', TestLists);
  RegisterTest('XsdTypes.HasValue', TestHasValue);
end;

end.
