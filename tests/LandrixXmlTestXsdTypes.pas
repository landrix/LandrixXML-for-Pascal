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
  Check(LandrixXmlXsdBuiltinType('duration') = nil, 'duration not supported');
  Check(LandrixXmlXsdBuiltinType('QName') = nil, 'QName not supported');
  CheckFacetError(Bool, xsfEnumeration, 'true', xecInvalidArgument, 'enumeration on boolean');
  CheckFacetError(Str, xsfTotalDigits, '3', xecInvalidArgument, 'totalDigits on a string');
  CheckFacetError(Dec, xsfMaxLength, '3', xecInvalidArgument, 'maxLength on a decimal');
  CheckFacetError(Dec, xsfMaxInclusive, 'abc', xecInvalidArgument, 'invalid bound');
  CheckFacetError(Str, xsfMaxLength, '-1', xecInvalidArgument, 'negative length');
  CheckFacetError(Str, xsfWhiteSpace, 'preserve', xecInvalidArgument, 'weaker whiteSpace');
  CheckFacetError(Str, xsfPattern, '[a', xecRegex, 'invalid pattern');
end;

procedure TestUnionFacets;
var
  U1: TLandrixXmlXsdSimpleType;
begin
  U1 := TLandrixXmlXsdSimpleType.CreateUnion([LandrixXmlXsdBuiltinType('int'),
    LandrixXmlXsdBuiltinType('date')], '', U('u'));
  try
    try
      U1.AddFacet(xsfPattern, U('[0-9]+'));
      FailNotRaised('ELandrixXmlError for a facet on a union');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecUnsupported), Ord(E.Code), 'facet on a union');
    end;
  finally
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
    Check(LandrixXmlXsdBuiltinType('ENTITIES') = nil, 'ENTITIES is not supported');
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

procedure Register;
begin
  RegisterTest('XsdTypes.GeneratedData', TestGeneratedData);
  RegisterTest('XsdTypes.WhiteSpace', TestWhiteSpace);
  RegisterTest('XsdTypes.FacetRules', TestFacetRules);
  RegisterTest('XsdTypes.UnionFacets', TestUnionFacets);
  RegisterTest('XsdTypes.CompareValues', TestCompareValues);
  RegisterTest('XsdTypes.ValueFields', TestValueFields);
  RegisterTest('XsdTypes.Lists', TestLists);
end;

end.
