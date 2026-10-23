{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for LandrixXmlRegex: generated cases (tests/data/regex, results
  from Saxon HE 12), the XSD dialect, unsupported constructs, error codes
  and linear running time. }

unit LandrixXmlTestRegex;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlRegex,
  LandrixXmlTestFramework;

type
  TFields = array of string;

function U(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

function N(const S: TLandrixXmlUtf8): string;
begin
  Result := LandrixXmlUtf8ToString(S);
end;

function DataFile(const Name: string): string;
begin
  Result := IncludeTrailingPathDelimiter(RepositoryRoot) + 'tests' + PathDelim + 'data' +
    PathDelim + 'regex' + PathDelim + Name;
end;

{ TAB separated fields, empty fields kept. }
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

{ A field of the data file: printable ASCII, or "hex:" and UTF-8 bytes. }
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

function Evaluate(const Fields: TFields): TLandrixXmlUtf8;
var
  R: TLandrixXmlRegex;
  Mode: TLandrixXmlRegexMode;
  Tokens: TLandrixXmlUtf8Array;
  I: Integer;
begin
  Tokens := nil;
  if Fields[0] = 'xsd' then
    Mode := xrmXsd
  else
    Mode := xrmXPath;
  R := nil;
  try
    try
      R := TLandrixXmlRegex.Create(Decode(Fields[1]), Mode);
      if (Fields[0] = 'xsd') or (Fields[0] = 'matches') then
      begin
        if R.Matches(Decode(Fields[2])) then
          Result := 'true'
        else
          Result := 'false';
      end
      else if Fields[0] = 'replace' then
        Result := R.Replace(Decode(Fields[2]), Decode(Fields[3]))
      else if Fields[0] = 'tokenize' then
      begin
        Tokens := R.Tokenize(Decode(Fields[2]));
        Result := U(IntToStr(Length(Tokens)));
        for I := 0 to Integer(Length(Tokens)) - 1 do
          Result := Result + #9 + Tokens[I];
      end
      else
        Result := U('unknown kind ' + Fields[0]);
    except
      on E: ELandrixXmlError do
      begin
        if E.Code = xecRegex then
          Result := 'error'
        else if E.Code = xecUnsupported then
          Result := 'unsupported'
        else
          Result := U('unexpected error: ' + E.Message);
      end;
    end;
  finally
    R.Free;
  end;
end;

{ The expected result of a line, decoded. }
function Expected(const Fields: TFields): TLandrixXmlUtf8;
var
  First, I: Integer;
begin
  if Fields[0] = 'replace' then
    First := 4
  else
    First := 3;
  if (Fields[0] = 'tokenize') and (Fields[First] <> 'error') and (Fields[First] <> 'unsupported') then
  begin
    Result := U(Fields[First]);
    for I := First + 1 to Integer(Length(Fields)) - 1 do
      Result := Result + #9 + Decode(Fields[I]);
  end
  else if Fields[0] = 'replace' then
  begin
    if (Fields[First] = 'error') or (Fields[First] = 'unsupported') then
      Result := U(Fields[First])
    else
      Result := Decode(Fields[First]);
  end
  else
    Result := U(Fields[First]);
end;

procedure TestGeneratedData;
var
  L: TStringList;
  K: Integer;
  Fields: TFields;
begin
  Fields := nil;
  L := TStringList.Create;
  try
    L.LoadFromFile(DataFile('cases.txt'));
    Check(L.Count > 4000, 'regex cases present');
    for K := 0 to L.Count - 1 do
    begin
      Fields := SplitTabs(L[K]);
      CheckEqualsUtf8(Expected(Fields), Evaluate(Fields),
        'line ' + IntToStr(K + 1) + ': ' + L[K]);
    end;
  finally
    L.Free;
  end;
end;

function XsdMatches(const Pattern, S: string): Boolean;
var
  R: TLandrixXmlRegex;
begin
  R := TLandrixXmlRegex.Create(U(Pattern), xrmXsd);
  try
    Result := R.Matches(U(S));
  finally
    R.Free;
  end;
end;

function XPathMatches(const Pattern, S: string): Boolean;
var
  R: TLandrixXmlRegex;
begin
  R := TLandrixXmlRegex.Create(U(Pattern), xrmXPath);
  try
    Result := R.Matches(U(S));
  finally
    R.Free;
  end;
end;

procedure CheckError(const Pattern: string; Mode: TLandrixXmlRegexMode;
  Code: TLandrixXmlErrorCode; const Name: string);
var
  R: TLandrixXmlRegex;
begin
  R := nil;
  try
    try
      R := TLandrixXmlRegex.Create(U(Pattern), Mode);
      FailNotRaised('ELandrixXmlError for ' + Name);
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(Code), Ord(E.Code), Name + ': ' + E.Message);
    end;
  finally
    R.Free;
  end;
end;

procedure TestXsdDialect;
begin
  Check(XsdMatches('^a$', '^a$'), '^ and $ are characters in XSD');
  Check(not XsdMatches('^a$', 'a'), '^ and $ do not anchor in XSD');
  Check(XsdMatches('abc', 'abc'), 'whole string');
  Check(not XsdMatches('abc', 'xabc'), 'implicitly anchored at the start');
  Check(not XsdMatches('abc', 'abcx'), 'implicitly anchored at the end');
  Check(not XsdMatches('a|ab', 'abx'), 'alternatives anchored too');
  Check(XsdMatches('a|ab', 'ab'), 'second alternative');
  CheckError('a\$', xrmXsd, xecRegex, '\$ in XSD');
  CheckError('(?:a)', xrmXsd, xecRegex, '(?: in XSD');
  CheckError('a\1', xrmXsd, xecRegex, 'back-reference in XSD');
  Check(XPathMatches('a\$', 'a$'), '\$ in XPath');
  Check(not XPathMatches('^b', 'ab'), '^ anchors in XPath');
  Check(XPathMatches('b', 'ab'), 'XPath searches');
end;

function XPath20Matches(const Pattern, S: string): Boolean;
var
  R: TLandrixXmlRegex;
begin
  R := TLandrixXmlRegex.Create(U(Pattern), xrmXPath20);
  try
    Result := R.Matches(U(S));
  finally
    R.Free;
  end;
end;

{ XPath 2.0: the syntax of XPath (anchors, searching, \$) with the
  character classes of XML Schema 1.0 and no (?:...) groups. }
procedure TestXPath20Dialect;
begin
  Check(XPath20Matches('b', 'ab'), 'XPath 2.0 searches');
  Check(not XPath20Matches('^b', 'ab'), '^ anchors in XPath 2.0');
  Check(XPath20Matches('a\$', 'a$'), '\$ in XPath 2.0');
  Check(XPath20Matches('[a-]', '-'), 'a hyphen at the end of a class');
  Check(XPath20Matches('[-a]', '-'), 'a hyphen at the start of a class');
  Check(XPath20Matches('[a-z-[aeiou]]', 'b'), 'a subtraction');
  Check(XPath20Matches('[a-z--[x]]', '-'), 'a hyphen at the end of the positive group, before a subtraction');
  Check(XPath20Matches('[a--[x]]', '-'), 'a hyphen after a character, before a subtraction');
  Check(not XPath20Matches('[a-z--[x]]', 'x'), 'the subtraction still applies');
  CheckError('[0-9-.]', xrmXPath20, xecRegex, 'a hyphen after a range (XML Schema 1.0)');
  Check(XPathMatches('[0-9-.]', '-'), 'the same in the Saxon dialect');
  CheckError('(?:a)', xrmXPath20, xecRegex, '(?: in XPath 2.0');
  CheckError('(a)\1', xrmXPath20, xecUnsupported, 'a back-reference in XPath 2.0');
  CheckError('a*?', xrmXPath20, xecUnsupported, 'a reluctant quantifier in XPath 2.0');
end;

procedure TestUnsupported;
var
  R: TLandrixXmlRegex;
begin
  CheckError('(a)\1', xrmXPath, xecUnsupported, 'back-reference');
  CheckError('\p{IsBasicLatin}', xrmXPath, xecUnsupported, 'block escape');
  CheckError('a*?', xrmXPath, xecUnsupported, 'reluctant quantifier');
  R := nil;
  try
    try
      R := TLandrixXmlRegex.Create(U('a'), xrmXPath, U('i'));
      FailNotRaised('ELandrixXmlError for flags');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecUnsupported), Ord(E.Code), 'flags');
    end;
  finally
    R.Free;
  end;
end;

procedure TestProperties;
var
  R: TLandrixXmlRegex;
begin
  R := TLandrixXmlRegex.Create(U('(a)(?:b)(c(d))?'), xrmXPath);
  try
    CheckEquals(3, R.GroupCount, 'group count');
    Check(not R.MatchesEmptyString, 'does not match empty');
  finally
    R.Free;
  end;
  R := TLandrixXmlRegex.Create(U('x|'), xrmXPath);
  try
    Check(R.MatchesEmptyString, 'x| matches empty');
  finally
    R.Free;
  end;
end;

{ Patterns that make backtracking engines run for ages. }
procedure TestLinearTime;
var
  R: TLandrixXmlRegex;
  S: string;
  Started: TDateTime;
begin
  S := StringOfChar('a', 20000);
  Started := Now;
  R := TLandrixXmlRegex.Create(U('(a*)*b'), xrmXPath);
  try
    Check(not R.Matches(U(S)), '(a*)*b on a...a');
  finally
    R.Free;
  end;
  { the XRechnung telephone pattern on digits without a match at the end }
  R := TLandrixXmlRegex.Create(U('^.*([0-9].*){3,}x$'), xrmXPath);
  try
    Check(not R.Matches(U(StringOfChar('1', 3000))), 'telephone-like pattern');
  finally
    R.Free;
  end;
  Check(Now - Started < 20 / (24 * 3600), 'well below 20 seconds');
end;

{ S as raw UTF-8: a native string would lose these characters on Delphi 6. }
function XsdMatchesUtf8(const Pattern: string; const S: TLandrixXmlUtf8): Boolean;
var
  R: TLandrixXmlRegex;
begin
  R := TLandrixXmlRegex.Create(U(Pattern), xrmXsd);
  try
    Result := R.Matches(S);
  finally
    R.Free;
  end;
end;

procedure TestUnicode;
begin
  { U+0663 ARABIC-INDIC DIGIT THREE is \d, U+00BD VULGAR FRACTION ONE HALF is not }
  Check(XsdMatchesUtf8('\d', Utf8Bytes([$D9, $A3])), 'Nd digit');
  Check(not XsdMatchesUtf8('\d', Utf8Bytes([$C2, $BD])), 'No is not \d');
  Check(XsdMatchesUtf8('.', Utf8Bytes([$F0, $9F, $98, $80])), '. matches one supplementary character');
  Check(not XsdMatchesUtf8('..', Utf8Bytes([$F0, $9F, $98, $80])),
    'a supplementary character is one character');
end;

{ XSD mode follows XML Schema 1.0 as Xerces (results checked with the JDK
  validator); the XPath rules come from Saxon through the generated data. }
procedure TestXsdHyphens;
const
  Valid: array[0..9] of string = ('[--]', '[-]', '[-a-z]', '[a-z-]', '[a-z-[x]]', '[\--z]',
    '[--[a]]', '[^-a]', '[\d-]', '[^--]');
  Invalid: array[0..11] of string = ('[a-z-0-9]', '[\d-z]', '[--z]', '[a-z--[x]]', '[a-k-z]',
    '[A-Za-z0-9-_]', '[\w-.]', '[a--]', '[\d--z]', '[!--]', '[a--[x]]', '[a-z---[x]]');
var
  I: Integer;
begin
  { the valid patterns must compile; what they match is checked below }
  for I := 0 to High(Valid) do
    XsdMatches(Valid[I], '-');
  for I := 0 to High(Invalid) do
    CheckError(Invalid[I], xrmXsd, xecRegex, 'XSD ' + Invalid[I]);
  Check(XsdMatches('[--]+', '--'), '[--] is a hyphen');
  Check(not XsdMatches('[--]', 'a'), '[--] is only a hyphen');
  Check(XsdMatches('[\--z]+', '-az'), 'escaped hyphen starts a range');
  Check(not XsdMatches('[a-z-[x]]', 'x'), 'subtraction after a range');
  Check(XsdMatches('[--[a]]', '-'), 'hyphen minus a');
  Check(not XsdMatches('[^--]', '-'), 'negated hyphen');
  Check(XPathMatches('[a-z-0-9]', '-'), 'XPath: hyphen after a range is literal');
  Check(XPathMatches('^[\w-.]+$', 'a-b.c'), 'XPath: hyphen after a class escape is literal');
end;

procedure CheckLimit(const Pattern: string; const Name: string);
var
  Started: TDateTime;
begin
  Started := Now;
  CheckError(Pattern, xrmXPath, xecLimit, Name);
  Check(Now - Started < 2 / (24 * 3600), Name + ': fails fast');
end;

{ Oversized programs fail before they are built; large ones compile in
  linear time and run without recursion. }
procedure TestLimits;
var
  R: TLandrixXmlRegex;
  Started: TDateTime;
  S: string;
  I: Integer;
begin
  CheckLimit('x{100001}', 'repetition above the limit');
  CheckLimit('x{99999}y{2}', 'repetitions above the limit together');
  CheckLimit('(x{1000}){200}', 'nested repetition above the limit');
  CheckLimit(StringOfChar('(', 1001) + 'a' + StringOfChar(')', 1001), 'nested groups');
  S := '[a';
  for I := 1 to 1001 do
    S := S + '-[a';
  CheckLimit(S + StringOfChar(']', 1002), 'nested subtractions');
  Started := Now;
  { (a?) is four instructions: 80000 in all, every split nested in the
    previous copy; a recursive thread walk overflowed the stack here }
  R := TLandrixXmlRegex.Create(U('(a?){20000}'), xrmXsd);
  try
    Check(R.Matches(U('aaa')), '(a?){20000} on aaa');
    Check(not R.Matches(U('aab')), '(a?){20000} on aab');
  finally
    R.Free;
  end;
  R := TLandrixXmlRegex.Create(U('x{0,49000}'), xrmXsd);
  try
    Check(R.Matches(U(StringOfChar('x', 100))), 'x{0,49000}');
  finally
    R.Free;
  end;
  Check(Now - Started < 20 / (24 * 3600), 'large programs well below 20 seconds');
end;

procedure TestInvalidUtf8;
var
  R: TLandrixXmlRegex;
begin
  R := nil;
  try
    try
      R := TLandrixXmlRegex.Create(Utf8Bytes([Ord('a'), $FF]), xrmXsd);
      FailNotRaised('ELandrixXmlError for a malformed pattern');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidUnicode), Ord(E.Code), 'malformed pattern');
    end;
  finally
    R.Free;
  end;
  R := TLandrixXmlRegex.Create(U('a'), xrmXPath);
  try
    try
      R.Matches(Utf8Bytes([Ord('a'), $C3]));
      FailNotRaised('ELandrixXmlError for malformed input');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidUnicode), Ord(E.Code), 'malformed input');
    end;
  finally
    R.Free;
  end;
end;

procedure TestCategories;
begin
  Check(XsdMatchesUtf8('\p{C}', Utf8Bytes([1])), 'Cc is in C');
  { U+0378 is unassigned in Unicode 6.2.0 }
  Check(XsdMatchesUtf8('\p{Cn}', Utf8Bytes([$CD, $B8])), 'unassigned is Cn');
  Check(not XsdMatchesUtf8('\p{Cn}', U('a')), 'a is not Cn');
  Check(XsdMatches('\P{Nd}', 'a'), 'a is not Nd');
  Check(not XsdMatches('\P{Nd}', '5'), '5 is Nd');
end;

procedure Register;
begin
  RegisterTest('Regex.GeneratedData', TestGeneratedData);
  RegisterTest('Regex.XsdDialect', TestXsdDialect);
  RegisterTest('Regex.XPath20Dialect', TestXPath20Dialect);
  RegisterTest('Regex.Unsupported', TestUnsupported);
  RegisterTest('Regex.Properties', TestProperties);
  RegisterTest('Regex.LinearTime', TestLinearTime);
  RegisterTest('Regex.Unicode', TestUnicode);
  RegisterTest('Regex.XsdHyphens', TestXsdHyphens);
  RegisterTest('Regex.Limits', TestLimits);
  RegisterTest('Regex.InvalidUtf8', TestInvalidUtf8);
  RegisterTest('Regex.Categories', TestCategories);
end;

end.
