{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for LandrixXmlXsdContent: generated cases (tests/data/xsdcontent,
  results from the Xerces validator of the Java runtime), the three ways
  of checking occurrence bounds, failure recovery, wildcards and all
  groups. }

unit LandrixXmlTestXsdContent;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  Classes,
  LandrixXmlBase,
  LandrixXmlXsdContent,
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
    PathDelim + 'xsdcontent' + PathDelim + Name;
end;

function Split(const Line: string; Separator: Char): TFields;
var
  P, N: Integer;
  Rest: string;
begin
  Result := nil;
  N := 0;
  Rest := Line;
  repeat
    P := Pos(Separator, Rest);
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

{ Model notation of the generator: S(...) sequence, C(...) choice, A(...)
  all group, a
  letter an element, "*" a ##any wildcard, an optional suffix gives min
  and max in braces (max u for unbounded). }
function ParseBounds(const S: string; var I: Integer; out MinOccurs, MaxOccurs: Integer): Boolean;
var
  Start: Integer;
begin
  MinOccurs := 1;
  MaxOccurs := 1;
  Result := True;
  if (I > Length(S)) or (S[I] <> '{') then
    Exit;
  Inc(I);
  Start := I;
  while S[I] <> ',' do
    Inc(I);
  MinOccurs := StrToInt(Copy(S, Start, I - Start));
  Inc(I);
  Start := I;
  while S[I] <> '}' do
    Inc(I);
  if Copy(S, Start, I - Start) = 'u' then
    MaxOccurs := LandrixXmlXsdUnbounded
  else
    MaxOccurs := StrToInt(Copy(S, Start, I - Start));
  Inc(I);
end;

function ParseParticle(const S: string; var I: Integer): TLandrixXmlXsdParticle;
var
  Kind: TLandrixXmlXsdParticleKind;
  Children: TList;
  MinOccurs, MaxOccurs, K: Integer;
  Name: string;
begin
  if ((S[I] = 'S') or (S[I] = 'C') or (S[I] = 'A')) and (I < Length(S)) and (S[I + 1] = '(') then
  begin
    if S[I] = 'S' then
      Kind := xpkSequence
    else if S[I] = 'A' then
      Kind := xpkAll
    else
      Kind := xpkChoice;
    Inc(I, 2);
    Children := TList.Create;
    try
      while S[I] <> ')' do
      begin
        if S[I] = ' ' then
          Inc(I);
        Children.Add(ParseParticle(S, I));
      end;
      Inc(I);
      ParseBounds(S, I, MinOccurs, MaxOccurs);
      Result := TLandrixXmlXsdParticle.CreateGroup(Kind, MinOccurs, MaxOccurs);
      for K := 0 to Integer(Children.Count) - 1 do
        Result.Add(TLandrixXmlXsdParticle(Children[K]));
    finally
      Children.Free;
    end;
    Exit;
  end;
  Name := S[I];
  Inc(I);
  ParseBounds(S, I, MinOccurs, MaxOccurs);
  if Name = '*' then
  begin
    Result := TLandrixXmlXsdParticle.CreateWildcard(xncAny, nil, nil, MinOccurs, MaxOccurs);
    Exit;
  end;
  { local declarations: each element particle is its own declaration }
  Result := TLandrixXmlXsdParticle.CreateElement('', U(Name), nil, MinOccurs, MaxOccurs);
end;

function ParseModel(const S: string): TLandrixXmlXsdContentModel;
var
  I: Integer;
begin
  I := 1;
  Result := TLandrixXmlXsdContentModel.Create(ParseParticle(S, I));
end;

function IssueEntry(const Issue: TLandrixXmlXsdContentIssue; Position: Integer;
  const Child: TLandrixXmlUtf8; AtEnd: Boolean; Expected: TList): string;
var
  Code, Message: string;
begin
  LandrixXmlXsdContentIssueText(Issue, Child, '', Child, 'r', Expected, AtEnd, Code, Message);
  Result := IntToStr(Position) + ':' + Code + ':' + Message;
end;

{ The errors for the root element, in the generator's notation. }
function Evaluate(Model: TLandrixXmlXsdContentModel; const ChildText: string): string;
var
  State: TLandrixXmlXsdContentState;
  Children: TFields;
  Issue: TLandrixXmlXsdContentIssue;
  Issues: TLandrixXmlXsdContentIssues;
  Expected: TList;
  K, N: Integer;
begin
  Result := '';
  Children := nil;
  if ChildText <> '' then
    Children := Split(ChildText, ',');
  N := Integer(Length(Children));
  State := TLandrixXmlXsdContentState.Create;
  Expected := TList.Create;
  try
    State.Start(Model);
    for K := 0 to N - 1 do
    begin
      State.Step('', U(Children[K]), Issue);
      if Issue.Kind <> xciNone then
      begin
        State.Expected(Expected);
        if Result <> '' then
          Result := Result + '|';
        Result := Result + IssueEntry(Issue, K, U(Children[K]), False, Expected);
      end;
    end;
    Issues := State.Finish;
    for K := 0 to Integer(Length(Issues)) - 1 do
    begin
      State.Expected(Expected);
      if Result <> '' then
        Result := Result + '|';
      Result := Result + IssueEntry(Issues[K], N, '', True, Expected);
    end;
  finally
    Expected.Free;
    State.Free;
  end;
end;

procedure CheckGeneratedData(const FileName: string; MinCount: Integer);
var
  L: TStringList;
  K, MismatchCount: Integer;
  Fields: TFields;
  Model: TLandrixXmlXsdContentModel;
  Got, Mismatches: string;
  Ok: Boolean;
begin
  Fields := nil;
  Mismatches := '';
  MismatchCount := 0;
  L := TStringList.Create;
  try
    L.LoadFromFile(DataFile(FileName));
    Check(L.Count > MinCount, FileName + ': content model cases present');
    for K := 0 to L.Count - 1 do
    begin
      Fields := Split(L[K], #9);
      Model := ParseModel(Fields[0]);
      try
        Got := Evaluate(Model, Fields[1]);
      finally
        Model.Free;
      end;
      { the JDK throws where a counted maxOccurs is exceeded }
      if Fields[2] = 'jdk-exception' then
        Ok := Pos('No child element ''{', Got) > 0
      else
        Ok := Got = Fields[2];
      if not Ok then
      begin
        Inc(MismatchCount);
        if MismatchCount <= 25 then
          Mismatches := Mismatches + #10 + '  line ' + IntToStr(K + 1) + ': ' + L[K] + #10 +
            '    got ' + Got;
      end;
    end;
    Check(MismatchCount = 0, FileName + ': ' + IntToStr(MismatchCount) + ' differences from Xerces:' +
      Mismatches);
  finally
    L.Free;
  end;
end;

procedure TestGeneratedData;
begin
  CheckGeneratedData('cases.txt', 3000);
end;

procedure TestGeneratedAllGroups;
begin
  CheckGeneratedData('all.txt', 2000);
end;

{ An all group must reject Child; the caller keeps Child then. }
procedure CheckAllRejects(Child: TLandrixXmlXsdParticle; const What: string);
var
  Root: TLandrixXmlXsdParticle;
  Added: Boolean;
begin
  Root := TLandrixXmlXsdParticle.CreateGroup(xpkAll, 1, 1);
  Added := False;
  try
    try
      Root.Add(Child);
      Added := True;
      FailNotRaised(What + ' in an all group');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidArgument), Ord(E.Code), What);
    end;
  finally
    if not Added then
      Child.Free;
    Root.Free;
  end;
end;

{ All groups through the API: what a group may hold and where it may
  stand, the expected list, an optional group, ambiguity }
procedure TestAllGroups;
var
  Model: TLandrixXmlXsdContentModel;
  Root, Inner: TLandrixXmlXsdParticle;
  State: TLandrixXmlXsdContentState;
  Issue: TLandrixXmlXsdContentIssue;
  First, Second: TLandrixXmlXsdParticle;
  List: TList;
begin
  CheckAllRejects(TLandrixXmlXsdParticle.CreateElement('', U('a'), nil, 0, 2), 'maxOccurs 2');
  CheckAllRejects(TLandrixXmlXsdParticle.CreateElement('', U('a'), nil, 0, 0), 'maxOccurs 0');
  CheckAllRejects(TLandrixXmlXsdParticle.CreateGroup(xpkSequence, 1, 1), 'a sequence');
  { an all group below the root, an all group occurring twice }
  Root := TLandrixXmlXsdParticle.CreateGroup(xpkSequence, 1, 1);
  try
    Inner := TLandrixXmlXsdParticle.CreateGroup(xpkAll, 1, 1);
    Root.Add(Inner);
    try
      TLandrixXmlXsdContentModel.Create(Root).Free;
      FailNotRaised('an all group in a sequence');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidArgument), Ord(E.Code), 'all group in a sequence');
    end;
  finally
    Root.Free;
  end;
  Root := TLandrixXmlXsdParticle.CreateGroup(xpkAll, 1, 2);
  try
    try
      TLandrixXmlXsdContentModel.Create(Root).Free;
      FailNotRaised('an all group with maxOccurs 2');
    except
      on E: ELandrixXmlError do
        CheckEquals(Ord(xecInvalidArgument), Ord(E.Code), 'all group with maxOccurs 2');
    end;
  finally
    Root.Free;
  end;
  Model := ParseModel('A(a b{0,1} c){0,1}');
  State := TLandrixXmlXsdContentState.Create;
  List := TList.Create;
  try
    Check(not Model.FindAmbiguity(First, Second), 'distinct names: unambiguous');
    State.Start(Model);
    CheckEquals(0, Integer(Length(State.Finish)), 'an optional all group may stay empty');
    State.Start(Model);
    Check(State.Step('', U('c'), Issue) = Model.Leaves[2], 'c first');
    State.Expected(List);
    CheckEquals(2, Integer(List.Count), 'a and b still expected');
    Check((List[0] = Model.Leaves[0]) and (List[1] = Model.Leaves[1]), 'in the order of the group');
    CheckEquals(1, Integer(Length(State.Finish)), 'a is missing');
    Check(State.Step('', U('a'), Issue) = Model.Leaves[0], 'then a');
    CheckEquals(0, Integer(Length(State.Finish)), 'complete without b');
    Check(State.Step('', U('c'), Issue) = Model.Leaves[2], 'c again: still looked up');
    Check(Issue.Kind = xciUnexpected, 'c twice');
    Check(State.Failed, 'failed');
  finally
    List.Free;
    State.Free;
    Model.Free;
  end;
  Model := ParseModel('A(a b a{0,1})');
  try
    Check(Model.FindAmbiguity(First, Second), 'a twice: ambiguous');
    Check((First = Model.Leaves[0]) and (Second = Model.Leaves[2]), 'the two a, in order');
  finally
    Model.Free;
  end;
end;

procedure TestBoundsChecks;
var
  Model: TLandrixXmlXsdContentModel;
begin
  { all groups once: repeating }
  Model := ParseModel('S(a{1,3} b)');
  try
    Check(Model.RepeatingMode, 'S(a{1,3} b) uses repeating leaves');
    Check(Model.Leaves[0].BoundsCheck = xbcRepeating, 'a repeats');
    CheckEqualsStr('0:cvc-complex-type.2.4.a:Invalid content was found starting with element ''b''. ' +
      'One of ''{a}'' is expected.', Evaluate(Model, 'b'), 'b only: one error, no report at the end');
  finally
    Model.Free;
  end;
  { an optional choice: counted in the sequence, exact in the choice }
  Model := ParseModel('S(C(c d){0,1} a{1,3} C(e{0,2} f))');
  try
    Check(not Model.RepeatingMode, 'not repeating');
    Check(Model.Leaves[2].BoundsCheck = xbcCounted, 'a counted');
    Check(Model.Leaves[3].BoundsCheck = xbcExact, 'e exact inside a choice');
    CheckEqualsStr('5:cvc-complex-type.2.4.d:Invalid content was found starting with element ''r''. ' +
      'No child element ''{a}'' is expected at this point.', Evaluate(Model, 'a,a,a,a,f'), 'too many a at the end');
    CheckEqualsStr('', Evaluate(Model, 'c,a,a,f'), 'valid');
  finally
    Model.Free;
  end;
end;

{ Two particles of the same declaration are two entries with their own
  counters, as in Xerces (results checked with the JDK). }
procedure TestSameDeclarationTwice;
var
  Model: TLandrixXmlXsdContentModel;
  Root, Choice: TLandrixXmlXsdParticle;
  Decl: TObject;
begin
  Decl := TObject.Create;
  try
    Root := TLandrixXmlXsdParticle.CreateGroup(xpkSequence, 1, 1);
    Choice := TLandrixXmlXsdParticle.CreateGroup(xpkChoice, 0, 1);
    Choice.Add(TLandrixXmlXsdParticle.CreateElement('', U('x'), nil, 1, 1));
    Choice.Add(TLandrixXmlXsdParticle.CreateElement('', U('y'), nil, 1, 1));
    Root.Add(Choice);
    Root.Add(TLandrixXmlXsdParticle.CreateElement('', U('a'), Decl, 2, 3));
    Root.Add(TLandrixXmlXsdParticle.CreateElement('', U('b'), nil, 1, 1));
    Root.Add(TLandrixXmlXsdParticle.CreateElement('', U('a'), Decl, 2, 3));
    Model := TLandrixXmlXsdContentModel.Create(Root);
    try
      CheckEqualsStr('', Evaluate(Model, 'a,a,a,b,a,a'), 'each a counted on its own');
      CheckEqualsStr('4:cvc-complex-type.2.4.b:The content of element ''r'' is not complete. One of ' +
        '''{a}'' is expected.', Evaluate(Model, 'a,b,a,a'), 'first a too rare');
    finally
      Model.Free;
    end;
  finally
    Decl.Free;
  end;
end;

procedure TestFailureRecovery;
var
  Model: TLandrixXmlXsdContentModel;
  State: TLandrixXmlXsdContentState;
  Issue: TLandrixXmlXsdContentIssue;
  P: TLandrixXmlXsdParticle;
begin
  Model := ParseModel('S(a b{0,u} c)');
  State := TLandrixXmlXsdContentState.Create;
  try
    State.Start(Model);
    P := State.Step('', U('b'), Issue);
    Check(Issue.Kind = xciUnexpected, 'b before a');
    Check(State.Failed, 'failed');
    Check(P = Model.Leaves[1], 'b is still looked up');
    P := State.Step('', U('x'), Issue);
    Check((P = nil) and (Issue.Kind = xciNone), 'unknown child after failure: nothing');
    P := State.Step('', U('c'), Issue);
    Check((P = Model.Leaves[2]) and (Issue.Kind = xciNone), 'c found by name');
    CheckEquals(0, Integer(Length(State.Finish)), 'no incomplete report after a failure');
  finally
    State.Free;
    Model.Free;
  end;
end;

procedure TestWildcards;
var
  Model: TLandrixXmlXsdContentModel;
  Root: TLandrixXmlXsdParticle;
  Namespaces: TLandrixXmlUtf8Array;
  State: TLandrixXmlXsdContentState;
  Issue: TLandrixXmlXsdContentIssue;
  List: TList;
begin
  Namespaces := nil;
  SetLength(Namespaces, 1);
  Namespaces[0] := U('urn:t');
  Root := TLandrixXmlXsdParticle.CreateGroup(xpkSequence, 1, 1);
  Root.Add(TLandrixXmlXsdParticle.CreateElement(U('urn:t'), U('a'), nil, 1, 1));
  Root.Add(TLandrixXmlXsdParticle.CreateWildcard(xncNot, Namespaces, nil, 0, LandrixXmlXsdUnbounded));
  Model := TLandrixXmlXsdContentModel.Create(Root);
  State := TLandrixXmlXsdContentState.Create;
  List := TList.Create;
  try
    Check(Model.Leaves[1].Matches(U('urn:x'), U('w')), '##other matches another namespace');
    Check(not Model.Leaves[1].Matches('', U('w')), '##other does not match no namespace');
    Check(not Model.Leaves[1].Matches(U('urn:t'), U('w')), '##other does not match the target');
    State.Start(Model);
    State.Step(U('urn:t'), U('a'), Issue);
    Check(Issue.Kind = xciNone, 'a');
    State.Step(U('urn:x'), U('w'), Issue);
    Check(Issue.Kind = xciNone, 'w through the wildcard');
    State.Step('', U('w'), Issue);
    Check(Issue.Kind = xciUnexpected, 'w without namespace');
    State.Expected(List);
    CheckEqualsUtf8(U('{WC[##other:"urn:t"]}'), LandrixXmlXsdExpectedText(List), 'expected text');
  finally
    List.Free;
    State.Free;
    Model.Free;
  end;
end;

{ tests/data/xsdcontent/upa.txt: random models and the verdict of Xerces'
  Unique Particle Attribution check (tools/gen-xsdcontent-testdata.py
  --upa) }
procedure TestUniqueParticleAttribution;
var
  L: TStringList;
  K, MismatchCount, Ambiguous: Integer;
  Fields: TFields;
  Model: TLandrixXmlXsdContentModel;
  First, Second: TLandrixXmlXsdParticle;
  Got, Mismatches: string;
begin
  Fields := nil;
  Mismatches := '';
  MismatchCount := 0;
  Ambiguous := 0;
  L := TStringList.Create;
  try
    L.LoadFromFile(DataFile('upa.txt'));
    Check(L.Count > 1000, 'UPA cases present');
    for K := 0 to L.Count - 1 do
    begin
      Fields := Split(L[K], #9);
      Model := ParseModel(Fields[0]);
      try
        if Model.FindAmbiguity(First, Second) then
          Got := 'cos-nonambig:' + LandrixXmlUtf8ToString(First.Display) + '|' +
            LandrixXmlUtf8ToString(Second.Display)
        else
          Got := 'ok';
      finally
        Model.Free;
      end;
      if Got <> 'ok' then
        Inc(Ambiguous);
      if Got <> Fields[1] then
      begin
        Inc(MismatchCount);
        if MismatchCount <= 25 then
          Mismatches := Mismatches + #10 + '  line ' + IntToStr(K + 1) + ': ' + L[K] + #10 +
            '    got ' + Got;
      end;
    end;
    Check(Ambiguous > 100, 'ambiguous models among the cases');
    { as Xerces: counted bounds outside the compact model }
    Model := ParseModel('S(a{2,2} a C(b c){0,2})');
    try
      Check(Model.FindAmbiguity(First, Second), 'counted a before a is ambiguous for Xerces');
    finally
      Model.Free;
    end;
    Model := ParseModel('S(a{2,2} a)');
    try
      Check(not Model.FindAmbiguity(First, Second), 'the compact model counts a{2,2} before a');
    finally
      Model.Free;
    end;
    Check(MismatchCount = 0, IntToStr(MismatchCount) + ' differences from Xerces:' + Mismatches);
  finally
    L.Free;
  end;
end;

{ Root: a choice of A and B; True if Xerces' UPA check finds them
  competing }
function Competing(A, B: TLandrixXmlXsdParticle): Boolean;
var
  Root: TLandrixXmlXsdParticle;
  Model: TLandrixXmlXsdContentModel;
  First, Second: TLandrixXmlXsdParticle;
begin
  Root := TLandrixXmlXsdParticle.CreateGroup(xpkChoice, 1, 1);
  Root.Add(A);
  Root.Add(B);
  Model := TLandrixXmlXsdContentModel.Create(Root);
  try
    Result := Model.FindAmbiguity(First, Second);
  finally
    Model.Free;
  end;
end;

function Names(const A, B: string): TLandrixXmlUtf8Array;
begin
  Result := nil;
  if B = '-' then
    SetLength(Result, 1)
  else
    SetLength(Result, 2);
  Result[0] := U(A);
  if B <> '-' then
    Result[1] := U(B);
end;

procedure TestWildcardOverlap;
var
  Model: TLandrixXmlXsdContentModel;
  First, Second: TLandrixXmlXsdParticle;
begin
  Check(not Competing(TLandrixXmlXsdParticle.CreateWildcard(xncNot, Names('urn:t', '-'), nil, 1, 1),
    TLandrixXmlXsdParticle.CreateWildcard(xncList, Names('', '-'), nil, 1, 1)), '##other and ##local');
  Check(not Competing(TLandrixXmlXsdParticle.CreateWildcard(xncNot, Names('urn:t', '-'), nil, 1, 1),
    TLandrixXmlXsdParticle.CreateWildcard(xncList, Names('urn:t', ''), nil, 1, 1)),
    '##other and ##targetNamespace ##local');
  Check(Competing(TLandrixXmlXsdParticle.CreateWildcard(xncNot, Names('urn:t', '-'), nil, 1, 1),
    TLandrixXmlXsdParticle.CreateWildcard(xncList, Names('urn:t', 'urn:x'), nil, 1, 1)),
    '##other and a list with another namespace');
  Check(Competing(TLandrixXmlXsdParticle.CreateWildcard(xncNot, Names('urn:t', '-'), nil, 1, 1),
    TLandrixXmlXsdParticle.CreateWildcard(xncNot, Names('urn:x', '-'), nil, 1, 1)), 'two ##other');
  Check(not Competing(TLandrixXmlXsdParticle.CreateWildcard(xncList, Names('urn:a', '-'), nil, 1, 1),
    TLandrixXmlXsdParticle.CreateWildcard(xncList, Names('urn:b', ''), nil, 1, 1)), 'disjoint lists');
  Check(Competing(TLandrixXmlXsdParticle.CreateWildcard(xncList, Names('urn:a', '-'), nil, 1, 1),
    TLandrixXmlXsdParticle.CreateElement(U('urn:a'), U('e'), nil, 1, 1)), 'list and an element in it');
  Check(not Competing(TLandrixXmlXsdParticle.CreateWildcard(xncNot, Names('', '-'), nil, 1, 1),
    TLandrixXmlXsdParticle.CreateElement('', U('e'), nil, 1, 1)), '##other without target and a local element');
  Check(not Competing(TLandrixXmlXsdParticle.CreateElement(U('urn:a'), U('e'), nil, 1, 1),
    TLandrixXmlXsdParticle.CreateElement('', U('e'), nil, 1, 1)), 'same local name in other namespaces');
  Check(not Competing(TLandrixXmlXsdParticle.CreateElement('', U('a'), nil, 0, 0),
    TLandrixXmlXsdParticle.CreateElement('', U('a'), nil, 1, 1)), 'a particle that cannot occur');
  Model := ParseModel('S(C(a{0,0} b) b)');
  try
    Check(not Model.FindAmbiguity(First, Second), 'a choice whose other particle cannot occur');
  finally
    Model.Free;
  end;
end;

{ 14 nested sequences 1..2 around an ambiguous pair: too many positions
  to check, taken as unambiguous instead of exhausting memory }
procedure TestUpaLimit;
var
  Model: TLandrixXmlXsdContentModel;
  P, Group: TLandrixXmlXsdParticle;
  First, Second: TLandrixXmlXsdParticle;
  I: Integer;
begin
  P := TLandrixXmlXsdParticle.CreateGroup(xpkSequence, 1, 2);
  P.Add(TLandrixXmlXsdParticle.CreateElement('', U('a'), nil, 0, 1));
  P.Add(TLandrixXmlXsdParticle.CreateElement('', U('a'), nil, 1, 1));
  for I := 1 to 14 do
  begin
    Group := TLandrixXmlXsdParticle.CreateGroup(xpkSequence, 1, 2);
    Group.Add(P);
    P := Group;
  end;
  Model := TLandrixXmlXsdContentModel.Create(P);
  try
    Check(not Model.FindAmbiguity(First, Second), 'too large: no verdict');
  finally
    Model.Free;
  end;
end;

procedure Register;
begin
  RegisterTest('XsdContent.GeneratedData', TestGeneratedData);
  RegisterTest('XsdContent.GeneratedAllGroups', TestGeneratedAllGroups);
  RegisterTest('XsdContent.AllGroups', TestAllGroups);
  RegisterTest('XsdContent.BoundsChecks', TestBoundsChecks);
  RegisterTest('XsdContent.SameDeclarationTwice', TestSameDeclarationTwice);
  RegisterTest('XsdContent.FailureRecovery', TestFailureRecovery);
  RegisterTest('XsdContent.Wildcards', TestWildcards);
  RegisterTest('XsdContent.UniqueParticleAttribution', TestUniqueParticleAttribution);
  RegisterTest('XsdContent.WildcardOverlap', TestWildcardOverlap);
  RegisterTest('XsdContent.UpaLimit', TestUpaLimit);
end;

end.
