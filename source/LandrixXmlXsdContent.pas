{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Content models of XML Schema complex types: a tree of particles
  (sequence, choice, element, wildcard, each with minOccurs and maxOccurs)
  checked against the child elements of an element, one child at a time.

  The checker interprets the particle tree directly with a stack of frames
  (particle, occurrence count, current child) and decides each child by one
  element of lookahead, which the Unique Particle Attribution rule of the
  schema makes unambiguous (it is assumed, not checked). It follows the
  validator built into the Java runtime (Xerces) in what it reports and
  where:
  - The expected elements are listed in the order of their particles in
    the model, one entry per particle (two references to the same
    declaration are two entries, as in Xerces).
  - Occurrence bounds other than 0..1, 1..1, 0..unbounded and
    1..unbounded on an element or wildcard are checked in one of three
    ways (TLandrixXmlXsdBoundsCheck), chosen as Xerces chooses its model:
    if every group of the model occurs exactly once (or wraps a single
    element that occurs once), such particles count their repetitions and
    report the occurrence codes 2.4.e to 2.4.j at the child that breaks
    them ("repeating"). Otherwise an element whose enclosing groups are
    all sequences (or single-particle groups) occurring once, and every
    wildcard, is treated as * or + and its bounds are checked when the
    parent ends ("counted"); the rest behave as if the particle were
    written out the given number of times ("exact").
  - After the first mismatch the state fails: no further order checks,
    no "incomplete" report at the end; later children are looked up by
    name among the model's particles.
  Known difference: Xerces keeps the counters of counted bounds in the
  shared content model, so an element of the same type nested inside
  resets the outer element's counts; here every element counts its own
  children, as the specification requires.

  The unit does not depend on the schema model: element and wildcard
  particles carry an opaque declaration object for the caller. }

unit LandrixXmlXsdContent;

{$I LandrixXml.inc}

interface

uses
  SysUtils,
  Classes,
  Contnrs,
  LandrixXmlBase;

const
  LandrixXmlXsdUnbounded = -1;

type
  TLandrixXmlXsdParticleKind = (xpkElement, xpkWildcard, xpkSequence, xpkChoice);

  TLandrixXmlXsdNamespaceConstraint = (
    xncAny,  { ##any }
    xncNot,  { ##other: neither Namespaces[0] nor no namespace }
    xncList  { one of Namespaces, '' standing for no namespace }
  );

  TLandrixXmlXsdBoundsCheck = (
    xbcExact,     { checked at each child, as if written out }
    xbcCounted,   { treated as * or +, bounds checked at the end }
    xbcRepeating  { checked at each child with the occurrence codes }
  );

  TLandrixXmlXsdParticle = class
  private
    FKind: TLandrixXmlXsdParticleKind;
    FMinOccurs: Integer;
    FMaxOccurs: Integer;
    FNamespaceUri: TLandrixXmlUtf8;
    FLocalName: TLandrixXmlUtf8;
    FConstraint: TLandrixXmlXsdNamespaceConstraint;
    FNamespaces: TLandrixXmlUtf8Array;
    FDecl: TObject;
    FChildren: TObjectList;
    { set when the model is compiled }
    FLeafIndex: Integer;
    FTermIndex: Integer;
    FBoundsCheck: TLandrixXmlXsdBoundsCheck;
    FEffectiveMin: Integer;
    FEffectiveMax: Integer;
    FNullable: Boolean;
    FBodyNullable: Boolean;
    FFirst: TList;
    function GetChildCount: Integer;
    function GetChild(Index: Integer): TLandrixXmlXsdParticle;
    function GetIsLeaf: Boolean;
  public
    { MaxOccurs = LandrixXmlXsdUnbounded for no upper bound. Decl is the
      caller's declaration object (not owned). }
    constructor CreateElement(const NamespaceUri, LocalName: TLandrixXmlUtf8; Decl: TObject;
      MinOccurs, MaxOccurs: Integer);
    constructor CreateWildcard(Constraint: TLandrixXmlXsdNamespaceConstraint;
      const Namespaces: TLandrixXmlUtf8Array; Decl: TObject; MinOccurs, MaxOccurs: Integer);
    constructor CreateGroup(Kind: TLandrixXmlXsdParticleKind; MinOccurs, MaxOccurs: Integer);
    destructor Destroy; override;
    { Appends Child to a sequence or choice and takes ownership. }
    procedure Add(Child: TLandrixXmlXsdParticle);
    { Element: same expanded name. Wildcard: the namespace is allowed. }
    function Matches(const NamespaceUri, LocalName: TLandrixXmlUtf8): Boolean;
    { As Xerces prints the particle in expected lists: name or
      "namespace":name for an element, WC[...] for a wildcard. }
    function Display: TLandrixXmlUtf8;
    property Kind: TLandrixXmlXsdParticleKind read FKind;
    property IsLeaf: Boolean read GetIsLeaf;
    property MinOccurs: Integer read FMinOccurs;
    property MaxOccurs: Integer read FMaxOccurs;
    property NamespaceUri: TLandrixXmlUtf8 read FNamespaceUri;
    property LocalName: TLandrixXmlUtf8 read FLocalName;
    property Constraint: TLandrixXmlXsdNamespaceConstraint read FConstraint;
    property Namespaces: TLandrixXmlUtf8Array read FNamespaces;
    property Decl: TObject read FDecl;
    property ChildCount: Integer read GetChildCount;
    property Children[Index: Integer]: TLandrixXmlXsdParticle read GetChild;
    { after compilation: the check of the occurrence bounds of a leaf }
    property BoundsCheck: TLandrixXmlXsdBoundsCheck read FBoundsCheck;
    { after compilation: position of a leaf in document order }
    property LeafIndex: Integer read FLeafIndex;
  end;

  TLandrixXmlXsdContentModel = class
  private
    FRoot: TLandrixXmlXsdParticle;
    FLeaves: TList;
    FTerms: TList;
    FRepeatingMode: Boolean;
    procedure Compile;
    function GetLeafCount: Integer;
    function GetLeaf(Index: Integer): TLandrixXmlXsdParticle;
    function GetTermCount: Integer;
    function GetTerm(Index: Integer): TLandrixXmlXsdParticle;
  public
    { Takes ownership of Root (a sequence or choice; nil for a model that
      allows no child element). Root must not change afterwards. }
    constructor Create(Root: TLandrixXmlXsdParticle);
    destructor Destroy; override;
    { The first term (element or wildcard, in document order) that matches;
      nil if none does. }
    function FindTerm(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlXsdParticle;
    property Root: TLandrixXmlXsdParticle read FRoot;
    property LeafCount: Integer read GetLeafCount;
    property Leaves[Index: Integer]: TLandrixXmlXsdParticle read GetLeaf;
    { the element and wildcard particles as Xerces lists them in expected
      lists and counts them: all leaves, in document order }
    property TermCount: Integer read GetTermCount;
    property Terms[Index: Integer]: TLandrixXmlXsdParticle read GetTerm;
    { True if occurrence bounds are checked with the occurrence codes }
    property RepeatingMode: Boolean read FRepeatingMode;
  end;

  TLandrixXmlXsdContentIssueKind = (
    xciNone,
    xciUnexpected,     { 2.4.a (something was expected) or 2.4.d }
    xciMaxExceeded,    { 2.4.e (something was expected) or 2.4.f }
    xciMinNotReached,  { 2.4.g / 2.4.h at a child, 2.4.i / 2.4.j at the end }
    xciIncomplete,     { 2.4.b with the expected list }
    xciCountedMin,     { 2.4.b with Term only (counted bounds) }
    xciCountedMax      { 2.4.d.1 with Term (counted bounds) }
  );

  TLandrixXmlXsdContentIssue = record
    Kind: TLandrixXmlXsdContentIssueKind;
    { the particle whose bounds are concerned (occurrence kinds) }
    Term: TLandrixXmlXsdParticle;
    MinOccurs: Integer;
    MaxOccurs: Integer;
    Count: Integer;
  end;
  TLandrixXmlXsdContentIssues = array of TLandrixXmlXsdContentIssue;

  { Internal, public only because Delphi 6 has no nested types. }
  TLandrixXmlXsdContentFrame = record
    Particle: TLandrixXmlXsdParticle;
    Count: Integer;
    Index: Integer;
    Fresh: Boolean;
  end;
  TLandrixXmlXsdContentFrames = array of TLandrixXmlXsdContentFrame;
  TLandrixXmlXsdContentConfigs = array of TLandrixXmlXsdContentFrames;
  TLandrixXmlXsdContentCounts = array of Integer;

  { The state of one element's content; reusable with Start. A model can
    be shared between threads, a state cannot. }
  TLandrixXmlXsdContentState = class
  private
    FModel: TLandrixXmlXsdContentModel;
    { the configurations (frame stacks) the children so far allow; several
      when nested repetitions of the same particles can be split in more
      than one way }
    FConfigs: TLandrixXmlXsdContentConfigs;
    FConfigLens: TLandrixXmlXsdContentCounts;
    FConfigCount: Integer;
    FNext: TLandrixXmlXsdContentConfigs;
    FNextLens: TLandrixXmlXsdContentCounts;
    FNextCount: Integer;
    FWork: TLandrixXmlXsdContentConfigs;
    FWorkLens: TLandrixXmlXsdContentCounts;
    FWorkCount: Integer;
    FCur: TLandrixXmlXsdContentFrames;
    FFailed: Boolean;
    FCounts: TLandrixXmlXsdContentCounts;
    function TryStep(const NamespaceUri, LocalName: TLandrixXmlUtf8): TLandrixXmlXsdParticle;
    function ConfigCanEnd(const Frames: TLandrixXmlXsdContentFrames; Len: Integer): Boolean;
    procedure OccurrenceOf(out Issue: TLandrixXmlXsdContentIssue; out Present: Boolean);
  public
    procedure Start(Model: TLandrixXmlXsdContentModel);
    { Takes the next child element. Returns the particle that decides how
      the child is validated (element or wildcard), nil if there is none.
      Issue.Kind is xciNone unless this child is the first mismatch; then
      the state fails, Expected still lists what was expected before it,
      and the result is the first term matching the child by name.
      After a failure every child is looked up that way, without issue. }
    function Step(const NamespaceUri, LocalName: TLandrixXmlUtf8;
      out Issue: TLandrixXmlXsdContentIssue): TLandrixXmlXsdParticle;
    { The terms allowed next, in document order; in a failed state those
      allowed before the mismatch. }
    procedure Expected(List: TList);
    { The issues when the element ends: xciIncomplete or xciMinNotReached
      if the content is not complete, else the counted bounds that are
      violated (also after a failure). }
    function Finish: TLandrixXmlXsdContentIssues;
    property Failed: Boolean read FFailed;
    property Model: TLandrixXmlXsdContentModel read FModel;
  end;

{ Formats an expected list as Xerces does: the entries joined by ', '
  in braces, such as a, "urn:x":b and WC[##any]. }
function LandrixXmlXsdExpectedText(List: TList): TLandrixXmlUtf8;

{ The cvc code and message of an issue, worded as in Xerces. At a child,
  ChildName is its qualified name as written and ChildNamespaceUri and
  ChildLocalName its expanded name; at the end of the element they are
  ignored. ParentName is the element's qualified name, Expected the list
  from TLandrixXmlXsdContentState.Expected. xciCountedMax, which the Java
  runtime up to version 21.0.6 cannot word (its message is missing and
  the validator throws), reads as later versions of the Java runtime word
  it: cvc-complex-type.2.4.d, "No child element ... is expected at this
  point" with the parent's name and the particle in braces. }
procedure LandrixXmlXsdContentIssueText(const Issue: TLandrixXmlXsdContentIssue;
  const ChildName, ChildNamespaceUri, ChildLocalName, ParentName: TLandrixXmlUtf8;
  Expected: TList; AtEnd: Boolean; out Code, Message: string);

implementation

function IsStandardBounds(MinOccurs, MaxOccurs: Integer): Boolean;
begin
  Result := ((MaxOccurs = 1) and ((MinOccurs = 0) or (MinOccurs = 1))) or
    ((MaxOccurs = LandrixXmlXsdUnbounded) and ((MinOccurs = 0) or (MinOccurs = 1)));
end;

{ ---------------------------------------------------------------------- }
{ TLandrixXmlXsdParticle                                                 }
{ ---------------------------------------------------------------------- }

constructor TLandrixXmlXsdParticle.CreateElement(const NamespaceUri, LocalName: TLandrixXmlUtf8;
  Decl: TObject; MinOccurs, MaxOccurs: Integer);
begin
  inherited Create;
  FKind := xpkElement;
  FNamespaceUri := NamespaceUri;
  FLocalName := LocalName;
  FDecl := Decl;
  FMinOccurs := MinOccurs;
  FMaxOccurs := MaxOccurs;
  FFirst := TList.Create;
end;

constructor TLandrixXmlXsdParticle.CreateWildcard(Constraint: TLandrixXmlXsdNamespaceConstraint;
  const Namespaces: TLandrixXmlUtf8Array; Decl: TObject; MinOccurs, MaxOccurs: Integer);
var
  I: Integer;
begin
  inherited Create;
  if (Constraint = xncNot) and (Length(Namespaces) <> 1) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, '##other needs exactly one namespace');
  FKind := xpkWildcard;
  FConstraint := Constraint;
  FNamespaces := nil;
  SetLength(FNamespaces, Length(Namespaces));
  for I := 0 to Integer(Length(Namespaces)) - 1 do
    FNamespaces[I] := Namespaces[I];
  FDecl := Decl;
  FMinOccurs := MinOccurs;
  FMaxOccurs := MaxOccurs;
  FFirst := TList.Create;
end;

constructor TLandrixXmlXsdParticle.CreateGroup(Kind: TLandrixXmlXsdParticleKind;
  MinOccurs, MaxOccurs: Integer);
begin
  inherited Create;
  if not (Kind in [xpkSequence, xpkChoice]) then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'A group is a sequence or a choice');
  FKind := Kind;
  FMinOccurs := MinOccurs;
  FMaxOccurs := MaxOccurs;
  FChildren := TObjectList.Create(True);
  FFirst := TList.Create;
end;

destructor TLandrixXmlXsdParticle.Destroy;
begin
  FChildren.Free;
  FFirst.Free;
  inherited Destroy;
end;

procedure TLandrixXmlXsdParticle.Add(Child: TLandrixXmlXsdParticle);
begin
  if FChildren = nil then
    raise ELandrixXmlError.CreateCode(xecInvalidOperation, 'Only a group has children');
  FChildren.Add(Child);
end;

function TLandrixXmlXsdParticle.GetChildCount: Integer;
begin
  if FChildren = nil then
    Result := 0
  else
    Result := Integer(FChildren.Count);
end;

function TLandrixXmlXsdParticle.GetChild(Index: Integer): TLandrixXmlXsdParticle;
begin
  Result := TLandrixXmlXsdParticle(FChildren[Index]);
end;

function TLandrixXmlXsdParticle.GetIsLeaf: Boolean;
begin
  Result := FKind in [xpkElement, xpkWildcard];
end;

function TLandrixXmlXsdParticle.Matches(const NamespaceUri, LocalName: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  Result := False;
  case FKind of
    xpkElement:
      Result := (LocalName = FLocalName) and (NamespaceUri = FNamespaceUri);
    xpkWildcard:
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
  else
    { groups match nothing themselves }
  end;
end;

function TLandrixXmlXsdParticle.Display: TLandrixXmlUtf8;
var
  I: Integer;
begin
  case FKind of
    xpkElement:
      if FNamespaceUri <> '' then
        Result := '"' + FNamespaceUri + '":' + FLocalName
      else
        Result := FLocalName;
    xpkWildcard:
      begin
        Result := 'WC[';
        case FConstraint of
          xncAny:
            Result := Result + '##any';
          xncNot:
            Result := Result + '##other:"' + FNamespaces[0] + '"';
          xncList:
            for I := 0 to Integer(Length(FNamespaces)) - 1 do
            begin
              if I > 0 then
                Result := Result + ',';
              Result := Result + '"' + FNamespaces[I] + '"';
            end;
        end;
        Result := Result + ']';
      end;
  else
    Result := '';
  end;
end;

function LandrixXmlXsdExpectedText(List: TList): TLandrixXmlUtf8;
var
  I: Integer;
begin
  Result := '{';
  for I := 0 to Integer(List.Count) - 1 do
  begin
    if I > 0 then
      Result := Result + ', ';
    Result := Result + TLandrixXmlXsdParticle(List[I]).Display;
  end;
  Result := Result + '}';
end;

{ Names and expected lists come from the schema; they are not shortened,
  as in Xerces. }
function Q(const S: TLandrixXmlUtf8): string;
begin
  Result := '''' + LandrixXmlEscapeForMessage(S, MaxInt) + '''';
end;

procedure LandrixXmlXsdContentIssueText(const Issue: TLandrixXmlXsdContentIssue;
  const ChildName, ChildNamespaceUri, ChildLocalName, ParentName: TLandrixXmlUtf8;
  Expected: TList; AtEnd: Boolean; out Code, Message: string);
var
  ExpectedText, Expanded, TermText: TLandrixXmlUtf8;
  Required: Integer;
begin
  ExpectedText := LandrixXmlXsdExpectedText(Expected);
  if ChildNamespaceUri <> '' then
    Expanded := '{"' + ChildNamespaceUri + '":' + ChildLocalName + '}'
  else
    Expanded := ChildLocalName;
  if Issue.Term <> nil then
    TermText := Issue.Term.Display
  else
    TermText := '';
  Required := Issue.MinOccurs - Issue.Count;
  Code := '';
  Message := '';
  case Issue.Kind of
    xciUnexpected:
      if Expected.Count > 0 then
      begin
        Code := 'cvc-complex-type.2.4.a';
        Message := 'Invalid content was found starting with element ' + Q(Expanded) + '. One of ' +
          Q(ExpectedText) + ' is expected.';
      end
      else
      begin
        Code := 'cvc-complex-type.2.4.d';
        Message := 'Invalid content was found starting with element ' + Q(ChildName) +
          '. No child element is expected at this point.';
      end;
    xciMaxExceeded:
      if Expected.Count > 0 then
      begin
        Code := 'cvc-complex-type.2.4.e';
        Message := Q(ChildName) + ' can occur a maximum of ''' + IntToStr(Issue.MaxOccurs) +
          ''' times in the current sequence. This limit was exceeded. At this point one of ' +
          Q(ExpectedText) + ' is expected.';
      end
      else
      begin
        Code := 'cvc-complex-type.2.4.f';
        Message := Q(TermText) + ' can occur a maximum of ''' + IntToStr(Issue.MaxOccurs) +
          ''' times in the current sequence. This limit was exceeded. No child element is expected at this point.';
      end;
    xciMinNotReached:
      if not AtEnd then
      begin
        if Required > 1 then
        begin
          Code := 'cvc-complex-type.2.4.h';
          Message := 'Invalid content was found starting with element ' + Q(ChildName) + '. ' +
            Q(TermText) + ' is expected to occur a minimum of ''' + IntToStr(Issue.MinOccurs) +
            ''' times in the current sequence. ''' + IntToStr(Required) +
            ''' more instances are required to satisfy this constraint.';
        end
        else
        begin
          Code := 'cvc-complex-type.2.4.g';
          Message := 'Invalid content was found starting with element ' + Q(ChildName) + '. ' +
            Q(TermText) + ' is expected to occur a minimum of ''' + IntToStr(Issue.MinOccurs) +
            ''' times in the current sequence. One more instance is required to satisfy this constraint.';
        end;
      end
      else if Required > 1 then
      begin
        Code := 'cvc-complex-type.2.4.j';
        Message := 'The content of element ' + Q(ParentName) + ' is not complete. ' + Q(TermText) +
          ' is expected to occur a minimum of ''' + IntToStr(Issue.MinOccurs) + ''' times. ''' +
          IntToStr(Required) + ''' more instances are required to satisfy this constraint.';
      end
      else
      begin
        Code := 'cvc-complex-type.2.4.i';
        Message := 'The content of element ' + Q(ParentName) + ' is not complete. ' + Q(TermText) +
          ' is expected to occur a minimum of ''' + IntToStr(Issue.MinOccurs) +
          ''' times. One more instance is required to satisfy this constraint.';
      end;
    xciIncomplete:
      begin
        Code := 'cvc-complex-type.2.4.b';
        Message := 'The content of element ' + Q(ParentName) + ' is not complete. One of ' +
          Q(ExpectedText) + ' is expected.';
      end;
    xciCountedMin:
      begin
        Code := 'cvc-complex-type.2.4.b';
        Message := 'The content of element ' + Q(ParentName) + ' is not complete. One of ' +
          Q('{' + TermText + '}') + ' is expected.';
      end;
    xciCountedMax:
      begin
        Code := 'cvc-complex-type.2.4.d';
        Message := 'Invalid content was found starting with element ' + Q(ParentName) + '. No child element ' +
          Q('{' + TermText + '}') + ' is expected at this point.';
      end;
  else
    { xciNone: no issue }
  end;
end;

{ ---------------------------------------------------------------------- }
{ TLandrixXmlXsdContentModel                                             }
{ ---------------------------------------------------------------------- }

constructor TLandrixXmlXsdContentModel.Create(Root: TLandrixXmlXsdParticle);
begin
  inherited Create;
  if (Root <> nil) and Root.IsLeaf then
    raise ELandrixXmlError.CreateCode(xecInvalidArgument, 'The root of a content model is a group');
  FRoot := Root;
  FLeaves := TList.Create;
  FTerms := TList.Create;
  if FRoot <> nil then
    Compile;
end;

destructor TLandrixXmlXsdContentModel.Destroy;
begin
  FRoot.Free;
  FLeaves.Free;
  FTerms.Free;
  inherited Destroy;
end;

{ Xerces' test for its compact model with repeating leaves: every group
  occurs exactly once, or holds nothing, or holds a single element or
  wildcard that occurs exactly once. }
function UsesRepeatingLeaves(P: TLandrixXmlXsdParticle): Boolean;
var
  I: Integer;
  Child: TLandrixXmlXsdParticle;
begin
  Result := True;
  if P.IsLeaf then
    Exit;
  if (P.MinOccurs <> 1) or (P.MaxOccurs <> 1) then
  begin
    if P.ChildCount = 1 then
    begin
      Child := P.Children[0];
      Result := Child.IsLeaf and (Child.MinOccurs = 1) and (Child.MaxOccurs = 1);
    end
    else
      Result := P.ChildCount = 0;
    Exit;
  end;
  for I := 0 to P.ChildCount - 1 do
    if not UsesRepeatingLeaves(P.Children[I]) then
    begin
      Result := False;
      Exit;
    end;
end;

{ Effective bounds and bound checks; Optimize as in Xerces: all enclosing
  groups are sequences or single-particle groups that occur once. }
procedure AssignBounds(P: TLandrixXmlXsdParticle; RepeatingMode, Optimize: Boolean);
var
  I: Integer;
  Child: TLandrixXmlXsdParticle;
  ChildOptimize: Boolean;
begin
  P.FEffectiveMin := P.FMinOccurs;
  P.FEffectiveMax := P.FMaxOccurs;
  P.FBoundsCheck := xbcExact;
  if P.IsLeaf then
  begin
    if not IsStandardBounds(P.FMinOccurs, P.FMaxOccurs) then
    begin
      if RepeatingMode then
        P.FBoundsCheck := xbcRepeating
      { in Xerces a wildcard is subsumed even outside such sequences }
      else if (Optimize and (P.FKind = xpkElement)) or (P.FKind = xpkWildcard) then
      begin
        P.FBoundsCheck := xbcCounted;
        if P.FMinOccurs > 0 then
          P.FEffectiveMin := 1;
        P.FEffectiveMax := LandrixXmlXsdUnbounded;
      end;
    end;
    Exit;
  end;
  ChildOptimize := Optimize and (P.FMinOccurs = 1) and (P.FMaxOccurs = 1) and
    ((P.FKind = xpkSequence) or (P.ChildCount = 1));
  for I := 0 to P.ChildCount - 1 do
    AssignBounds(P.Children[I], RepeatingMode, ChildOptimize);
  { a repeated group around one element that occurs once is a repeating
    element in Xerces' compact model: move the bounds to the element }
  if RepeatingMode and (P.ChildCount = 1) and ((P.FMinOccurs <> 1) or (P.FMaxOccurs <> 1)) then
  begin
    Child := P.Children[0];
    Child.FEffectiveMin := P.FMinOccurs;
    Child.FEffectiveMax := P.FMaxOccurs;
    if IsStandardBounds(P.FMinOccurs, P.FMaxOccurs) then
      Child.FBoundsCheck := xbcExact
    else
      Child.FBoundsCheck := xbcRepeating;
    P.FEffectiveMin := 1;
    P.FEffectiveMax := 1;
  end;
end;

{ Nullability and the leaves that can start the particle's body. }
procedure ComputeFirst(P: TLandrixXmlXsdParticle);
var
  I, J: Integer;
  Child: TLandrixXmlXsdParticle;
begin
  P.FFirst.Clear;
  if P.IsLeaf then
  begin
    P.FFirst.Add(P);
    P.FBodyNullable := False;
    P.FNullable := P.FEffectiveMin = 0;
    Exit;
  end;
  for I := 0 to P.ChildCount - 1 do
    ComputeFirst(P.Children[I]);
  if P.FKind = xpkSequence then
  begin
    P.FBodyNullable := True;
    for I := 0 to P.ChildCount - 1 do
    begin
      Child := P.Children[I];
      for J := 0 to Integer(Child.FFirst.Count) - 1 do
        P.FFirst.Add(Child.FFirst[J]);
      if not Child.FNullable then
      begin
        P.FBodyNullable := False;
        Break;
      end;
    end;
  end
  else
  begin
    { Xerces deviation: complex022. An empty choice matches nothing in
      XML Schema 1.0; Xerces lets it match the empty sequence }
    P.FBodyNullable := P.ChildCount = 0;
    for I := 0 to P.ChildCount - 1 do
    begin
      Child := P.Children[I];
      for J := 0 to Integer(Child.FFirst.Count) - 1 do
        P.FFirst.Add(Child.FFirst[J]);
      if Child.FNullable then
        P.FBodyNullable := True;
    end;
  end;
  P.FNullable := P.FBodyNullable or (P.FEffectiveMin = 0);
end;

procedure CollectLeaves(P: TLandrixXmlXsdParticle; Leaves: TList);
var
  I: Integer;
begin
  if P.IsLeaf then
  begin
    P.FLeafIndex := Integer(Leaves.Count);
    Leaves.Add(P);
    Exit;
  end;
  for I := 0 to P.ChildCount - 1 do
    CollectLeaves(P.Children[I], Leaves);
end;

procedure TLandrixXmlXsdContentModel.Compile;
var
  I: Integer;
  Leaf: TLandrixXmlXsdParticle;
begin
  FRepeatingMode := UsesRepeatingLeaves(FRoot);
  AssignBounds(FRoot, FRepeatingMode, True);
  ComputeFirst(FRoot);
  CollectLeaves(FRoot, FLeaves);
  { Xerces keeps one element map entry per particle }
  for I := 0 to Integer(FLeaves.Count) - 1 do
  begin
    Leaf := TLandrixXmlXsdParticle(FLeaves[I]);
    Leaf.FTermIndex := I;
    FTerms.Add(Leaf);
  end;
end;

function TLandrixXmlXsdContentModel.FindTerm(const NamespaceUri,
  LocalName: TLandrixXmlUtf8): TLandrixXmlXsdParticle;
var
  I: Integer;
begin
  for I := 0 to Integer(FTerms.Count) - 1 do
  begin
    Result := TLandrixXmlXsdParticle(FTerms[I]);
    if Result.Matches(NamespaceUri, LocalName) then
      Exit;
  end;
  Result := nil;
end;

function TLandrixXmlXsdContentModel.GetLeafCount: Integer;
begin
  Result := Integer(FLeaves.Count);
end;

function TLandrixXmlXsdContentModel.GetLeaf(Index: Integer): TLandrixXmlXsdParticle;
begin
  Result := TLandrixXmlXsdParticle(FLeaves[Index]);
end;

function TLandrixXmlXsdContentModel.GetTermCount: Integer;
begin
  Result := Integer(FTerms.Count);
end;

function TLandrixXmlXsdContentModel.GetTerm(Index: Integer): TLandrixXmlXsdParticle;
begin
  Result := TLandrixXmlXsdParticle(FTerms[Index]);
end;

{ ---------------------------------------------------------------------- }
{ TLandrixXmlXsdContentState                                             }
{ ---------------------------------------------------------------------- }

function CanStart(P: TLandrixXmlXsdParticle; const NamespaceUri, LocalName: TLandrixXmlUtf8): Boolean;
var
  I: Integer;
begin
  for I := 0 to Integer(P.FFirst.Count) - 1 do
    if TLandrixXmlXsdParticle(P.FFirst[I]).Matches(NamespaceUri, LocalName) then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;

const
  { Limit of the configurations explored for one child; realistic models
    need a handful. }
  MaxExplored = 100000;

{ Stores a copy of Src[0 .. Len - 1] as a new configuration, with room for
  Extra more frames; the index of the new entry. }
function AppendConfig(var List: TLandrixXmlXsdContentConfigs; var Lens: TLandrixXmlXsdContentCounts;
  var Count: Integer; const Src: TLandrixXmlXsdContentFrames; Len, Extra: Integer): Integer;
var
  I: Integer;
begin
  if Count = Length(List) then
  begin
    SetLength(List, 2 * Count + 4);
    SetLength(Lens, 2 * Count + 4);
  end;
  if Length(List[Count]) < Len + Extra then
    SetLength(List[Count], Len + Extra + 4);
  for I := 0 to Len - 1 do
    List[Count][I] := Src[I];
  Lens[Count] := Len;
  Result := Count;
  Inc(Count);
end;

{ A count beyond the lower bound of a particle without upper bound
  changes nothing, so it is kept at that bound and equal configurations
  stay equal. }
function Clamped(P: TLandrixXmlXsdParticle; Count: Integer): Integer;
var
  Limit: Integer;
begin
  Result := Count;
  if P.FEffectiveMax = LandrixXmlXsdUnbounded then
  begin
    Limit := P.FEffectiveMin;
    if Limit < 1 then
      Limit := 1;
    if Result > Limit then
      Result := Limit;
  end;
end;

function SameConfig(const A, B: TLandrixXmlXsdContentFrames; Len: Integer): Boolean;
var
  I: Integer;
begin
  for I := 0 to Len - 1 do
    if (A[I].Particle <> B[I].Particle) or (A[I].Count <> B[I].Count) or (A[I].Index <> B[I].Index) then
    begin
      Result := False;
      Exit;
    end;
  Result := True;
end;

procedure TLandrixXmlXsdContentState.Start(Model: TLandrixXmlXsdContentModel);
var
  I: Integer;
  Initial: TLandrixXmlXsdContentFrames;
begin
  FModel := Model;
  FFailed := False;
  FConfigCount := 0;
  if Model.FRoot <> nil then
  begin
    Initial := nil;
    SetLength(Initial, 1);
    Initial[0].Particle := Model.FRoot;
    Initial[0].Count := 0;
    Initial[0].Index := -1;
    Initial[0].Fresh := False;
    AppendConfig(FConfigs, FConfigLens, FConfigCount, Initial, 1, 4);
  end;
  SetLength(FCounts, Model.TermCount);
  for I := 0 to Model.TermCount - 1 do
    FCounts[I] := 0;
end;

{ Explores every way the configurations can take the child. A frame
  pushed during the exploration (Fresh) must take the child before it may
  be left again, so every branch ends after finitely many moves. The
  configurations that took the child go to FNext; the leaf they matched
  is the result (the same leaf in all of them, by Unique Particle
  Attribution). }
function TLandrixXmlXsdContentState.TryStep(const NamespaceUri,
  LocalName: TLandrixXmlUtf8): TLandrixXmlXsdParticle;
var
  I, J, K, Len, Top, Explored: Integer;
  P, Child: TLandrixXmlXsdParticle;
  Complete, Duplicate: Boolean;
begin
  Result := nil;
  FNextCount := 0;
  FWorkCount := 0;
  for I := FConfigCount - 1 downto 0 do
    AppendConfig(FWork, FWorkLens, FWorkCount, FConfigs[I], FConfigLens[I], 0);
  Explored := 0;
  while FWorkCount > 0 do
  begin
    Inc(Explored);
    if Explored > MaxExplored then
      raise ELandrixXmlError.CreateCode(xecLimit, 'Content model too ambiguous to check');
    Dec(FWorkCount);
    Len := FWorkLens[FWorkCount];
    if Length(FCur) < Len + 1 then
      SetLength(FCur, Len + 8);
    for I := 0 to Len - 1 do
      FCur[I] := FWork[FWorkCount][I];
    if Len = 0 then
      Continue;
    Top := Len - 1;
    P := FCur[Top].Particle;
    if P.IsLeaf then
    begin
      if ((P.FEffectiveMax = LandrixXmlXsdUnbounded) or (FCur[Top].Count < P.FEffectiveMax)) and
        P.Matches(NamespaceUri, LocalName) then
      begin
        K := AppendConfig(FNext, FNextLens, FNextCount, FCur, Len, 0);
        FNext[K][Top].Count := Clamped(P, FCur[Top].Count + 1);
        for I := 0 to Len - 1 do
          FNext[K][I].Fresh := False;
        Duplicate := False;
        for I := 0 to K - 1 do
          if (FNextLens[I] = Len) and SameConfig(FNext[I], FNext[K], Len) then
          begin
            Duplicate := True;
            Break;
          end;
        if Duplicate then
          Dec(FNextCount);
        if Result = nil then
          Result := P;
      end;
      if not FCur[Top].Fresh and (FCur[Top].Count >= P.FEffectiveMin) then
        AppendConfig(FWork, FWorkLens, FWorkCount, FCur, Len - 1, 0);
      Continue;
    end;
    { group: go on with the current iteration of a sequence }
    Complete := True;
    if (FCur[Top].Index >= 0) and (P.FKind = xpkSequence) then
    begin
      J := FCur[Top].Index + 1;
      while J < P.ChildCount do
      begin
        Child := P.Children[J];
        if CanStart(Child, NamespaceUri, LocalName) then
        begin
          K := AppendConfig(FWork, FWorkLens, FWorkCount, FCur, Len, 1);
          FWork[K][Top].Index := J;
          FWork[K][Len].Particle := Child;
          FWork[K][Len].Count := 0;
          FWork[K][Len].Index := -1;
          FWork[K][Len].Fresh := True;
          FWorkLens[K] := Len + 1;
        end;
        if not Child.FNullable then
        begin
          Complete := False;
          Break;
        end;
        Inc(J);
      end;
    end;
    if not Complete then
      Continue;
    { the iteration is complete (or none has started): another one }
    if ((P.FEffectiveMax = LandrixXmlXsdUnbounded) or (FCur[Top].Count < P.FEffectiveMax)) and
      CanStart(P, NamespaceUri, LocalName) then
      for J := 0 to P.ChildCount - 1 do
      begin
        Child := P.Children[J];
        if CanStart(Child, NamespaceUri, LocalName) then
        begin
          K := AppendConfig(FWork, FWorkLens, FWorkCount, FCur, Len, 1);
          FWork[K][Top].Count := Clamped(P, FCur[Top].Count + 1);
          FWork[K][Top].Index := J;
          FWork[K][Len].Particle := Child;
          FWork[K][Len].Count := 0;
          FWork[K][Len].Index := -1;
          FWork[K][Len].Fresh := True;
          FWorkLens[K] := Len + 1;
        end;
        if (P.FKind = xpkSequence) and not Child.FNullable then
          Break;
      end;
    { or leave the group }
    if not FCur[Top].Fresh and ((FCur[Top].Count >= P.FEffectiveMin) or P.FBodyNullable) then
      AppendConfig(FWork, FWorkLens, FWorkCount, FCur, Len - 1, 0);
  end;
end;

{ The occurrence information Xerces reports with a mismatch: present if
  the last matched particle is a repeating element or wildcard. }
procedure TLandrixXmlXsdContentState.OccurrenceOf(out Issue: TLandrixXmlXsdContentIssue;
  out Present: Boolean);
var
  P: TLandrixXmlXsdParticle;
  Top: Integer;
begin
  Issue.Kind := xciNone;
  Issue.Term := nil;
  Issue.MinOccurs := 0;
  Issue.MaxOccurs := 0;
  Issue.Count := 0;
  Present := False;
  if (FConfigCount = 0) or (FConfigLens[0] = 0) then
    Exit;
  Top := FConfigLens[0] - 1;
  P := FConfigs[0][Top].Particle;
  if P.IsLeaf and (P.FBoundsCheck = xbcRepeating) then
  begin
    Present := True;
    Issue.Term := P;
    Issue.MinOccurs := P.FEffectiveMin;
    Issue.MaxOccurs := P.FEffectiveMax;
    Issue.Count := FConfigs[0][Top].Count;
  end;
end;

function TLandrixXmlXsdContentState.Step(const NamespaceUri, LocalName: TLandrixXmlUtf8;
  out Issue: TLandrixXmlXsdContentIssue): TLandrixXmlXsdParticle;
var
  Swap: TLandrixXmlXsdContentConfigs;
  SwapLens: TLandrixXmlXsdContentCounts;
  Present: Boolean;
  List: TList;
begin
  Swap := nil;
  SwapLens := nil;
  Issue.Kind := xciNone;
  Issue.Term := nil;
  Issue.MinOccurs := 0;
  Issue.MaxOccurs := 0;
  Issue.Count := 0;
  if FFailed then
  begin
    Result := FModel.FindTerm(NamespaceUri, LocalName);
    Exit;
  end;
  Result := TryStep(NamespaceUri, LocalName);
  if Result <> nil then
  begin
    Swap := FConfigs;
    FConfigs := FNext;
    FNext := Swap;
    SwapLens := FConfigLens;
    FConfigLens := FNextLens;
    FNextLens := SwapLens;
    FConfigCount := FNextCount;
    if Result.FBoundsCheck = xbcCounted then
      Inc(FCounts[Result.FTermIndex]);
    Exit;
  end;
  { first mismatch: classify it as Xerces does, then fail }
  OccurrenceOf(Issue, Present);
  List := TList.Create;
  try
    Expected(List);
    if List.Count > 0 then
    begin
      if Present and (Issue.Count < Issue.MinOccurs) then
        Issue.Kind := xciMinNotReached
      else if Present and (Issue.MaxOccurs <> LandrixXmlXsdUnbounded) and
        (Issue.Count >= Issue.MaxOccurs) then
        Issue.Kind := xciMaxExceeded
      else
        Issue.Kind := xciUnexpected;
    end
    else if Present and (Issue.MaxOccurs <> LandrixXmlXsdUnbounded) and
      (Issue.Count >= Issue.MaxOccurs) then
      Issue.Kind := xciMaxExceeded
    else
      Issue.Kind := xciUnexpected;
  finally
    List.Free;
  end;
  if not Present then
    Issue.Term := nil;
  FFailed := True;
  Result := FModel.FindTerm(NamespaceUri, LocalName);
end;

procedure TLandrixXmlXsdContentState.Expected(List: TList);
var
  Marks: array of Boolean;
  C, I, J, Count: Integer;
  P: TLandrixXmlXsdParticle;
  Frames: TLandrixXmlXsdContentFrames;

  procedure MarkFirst(Q: TLandrixXmlXsdParticle);
  var
    K: Integer;
  begin
    for K := 0 to Integer(Q.FFirst.Count) - 1 do
      Marks[TLandrixXmlXsdParticle(Q.FFirst[K]).FTermIndex] := True;
  end;

begin
  List.Clear;
  Marks := nil;
  Frames := nil;
  SetLength(Marks, FModel.TermCount);
  for I := 0 to FModel.TermCount - 1 do
    Marks[I] := False;
  for C := 0 to FConfigCount - 1 do
  begin
    Frames := FConfigs[C];
    I := FConfigLens[C] - 1;
    while I >= 0 do
    begin
      P := Frames[I].Particle;
      Count := Frames[I].Count;
      if P.IsLeaf then
      begin
        if (P.FEffectiveMax = LandrixXmlXsdUnbounded) or (Count < P.FEffectiveMax) then
          Marks[P.FTermIndex] := True;
        if Count < P.FEffectiveMin then
          Break;
        Dec(I);
        Continue;
      end;
      if (Frames[I].Index >= 0) and (P.FKind = xpkSequence) then
      begin
        J := Frames[I].Index + 1;
        while J < P.ChildCount do
        begin
          MarkFirst(P.Children[J]);
          if not P.Children[J].FNullable then
            Break;
          Inc(J);
        end;
        if J < P.ChildCount then
          Break;
      end;
      if (P.FEffectiveMax = LandrixXmlXsdUnbounded) or (Count < P.FEffectiveMax) then
        MarkFirst(P);
      if not ((Count >= P.FEffectiveMin) or P.FBodyNullable) then
        Break;
      Dec(I);
    end;
  end;
  for I := 0 to FModel.TermCount - 1 do
    if Marks[I] then
      List.Add(FModel.FTerms[I]);
end;

function TLandrixXmlXsdContentState.ConfigCanEnd(const Frames: TLandrixXmlXsdContentFrames;
  Len: Integer): Boolean;
var
  I, J: Integer;
  P: TLandrixXmlXsdParticle;
begin
  Result := False;
  for I := Len - 1 downto 0 do
  begin
    P := Frames[I].Particle;
    if P.IsLeaf then
    begin
      if Frames[I].Count < P.FEffectiveMin then
        Exit;
      Continue;
    end;
    if (Frames[I].Index >= 0) and (P.FKind = xpkSequence) then
      for J := Frames[I].Index + 1 to P.ChildCount - 1 do
        if not P.Children[J].FNullable then
          Exit;
    if not ((Frames[I].Count >= P.FEffectiveMin) or P.FBodyNullable) then
      Exit;
  end;
  Result := True;
end;

function TLandrixXmlXsdContentState.Finish: TLandrixXmlXsdContentIssues;
var
  Issue: TLandrixXmlXsdContentIssue;
  Present, CanEnd: Boolean;
  I, N: Integer;
  Term: TLandrixXmlXsdParticle;
begin
  Result := nil;
  CanEnd := FConfigCount = 0;
  for I := 0 to FConfigCount - 1 do
    if ConfigCanEnd(FConfigs[I], FConfigLens[I]) then
    begin
      CanEnd := True;
      Break;
    end;
  if not FFailed and not CanEnd then
  begin
    OccurrenceOf(Issue, Present);
    if Present and (Issue.Count < Issue.MinOccurs) then
      Issue.Kind := xciMinNotReached
    else
    begin
      Issue.Kind := xciIncomplete;
      Issue.Term := nil;
    end;
    SetLength(Result, 1);
    Result[0] := Issue;
    Exit;
  end;
  { counted bounds, in term order, also after a failure }
  N := 0;
  for I := 0 to FModel.TermCount - 1 do
  begin
    Term := FModel.Terms[I];
    if Term.FBoundsCheck <> xbcCounted then
      Continue;
    Issue.Term := Term;
    Issue.MinOccurs := Term.FMinOccurs;
    Issue.MaxOccurs := Term.FMaxOccurs;
    Issue.Count := FCounts[I];
    if FCounts[I] < Term.FMinOccurs then
      Issue.Kind := xciCountedMin
    else if (Term.FMaxOccurs <> LandrixXmlXsdUnbounded) and (FCounts[I] > Term.FMaxOccurs) then
      Issue.Kind := xciCountedMax
    else
      Continue;
    SetLength(Result, N + 1);
    Result[N] := Issue;
    Inc(N);
  end;
end;

end.
