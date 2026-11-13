{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for the XPath tree: node order, attributes, merged text, names,
  string values, SchXslt locations and the namespaces in scope, built
  from the reader and from the DOM. }

unit LandrixXmlTestXPathTree;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  LandrixXmlBase,
  LandrixXmlDom,
  LandrixXmlXPathTree,
  LandrixXmlTestFramework;

const
  Sample =
    '<?xml version="1.0"?>' + #10 +
    '<!-- before -->' + #10 +
    '<r:Inv xmlns:r="urn:r" xmlns="urn:d" id="7" r:x="y">' + #10 +
    '  <a>one<![CDATA[ two]]></a>' + #10 +
    '  <a/>' + #10 +
    '  <b p="q"><!-- c --><?pi data?>tail</b>' + #10 +
    '  <a>three</a>' + #10 +
    '</r:Inv>';

const
  { every node except the document in document order, as Saxon lists
    //node() | //@* with SchXslt's location function }
  SaxonLocations: array[0..18] of string = (
    '/comment()[1]',
    '/Q{urn:r}Inv[1]',
    '/Q{urn:r}Inv[1]/@Q{}id',
    '/Q{urn:r}Inv[1]/@Q{urn:r}x',
    '/Q{urn:r}Inv[1]/text()[1]',
    '/Q{urn:r}Inv[1]/Q{urn:d}a[1]',
    '/Q{urn:r}Inv[1]/Q{urn:d}a[1]/text()[1]',
    '/Q{urn:r}Inv[1]/text()[2]',
    '/Q{urn:r}Inv[1]/Q{urn:d}a[2]',
    '/Q{urn:r}Inv[1]/text()[3]',
    '/Q{urn:r}Inv[1]/Q{urn:d}b[1]',
    '/Q{urn:r}Inv[1]/Q{urn:d}b[1]/@Q{}p',
    '/Q{urn:r}Inv[1]/Q{urn:d}b[1]/comment()[1]',
    '/Q{urn:r}Inv[1]/Q{urn:d}b[1]/processing-instruction("pi")[1]',
    '/Q{urn:r}Inv[1]/Q{urn:d}b[1]/text()[1]',
    '/Q{urn:r}Inv[1]/text()[4]',
    '/Q{urn:r}Inv[1]/Q{urn:d}a[3]',
    '/Q{urn:r}Inv[1]/Q{urn:d}a[3]/text()[1]',
    '/Q{urn:r}Inv[1]/text()[5]');

const
  { a document with the cases the data model has rules for, and the
    locations Saxon gives its nodes (same listing as above) }
  Tricky =
    '<?pi0 top?><!--c0--><r xmlns:a="urn:x" xmlns:b="urn:x" a:k="1" b:j="2" xml:lang="de">' +
    't1<!--c1-->t2<?p?>t3<![CDATA[c]]><![CDATA[d]]><a:e/><b:e/><e/>&amp;<![CDATA[]]>' +
    '<f><![CDATA[]]></f><g><!-- only --></g></r><!--c2--><?pi0?>';
  TrickyLocations: array[0..19] of string = (
    '/processing-instruction("pi0")[1]',
    '/comment()[1]',
    '/Q{}r[1]',
    '/Q{}r[1]/@Q{urn:x}k',
    '/Q{}r[1]/@Q{urn:x}j',
    '/Q{}r[1]/@Q{http://www.w3.org/XML/1998/namespace}lang',
    '/Q{}r[1]/text()[1]',
    '/Q{}r[1]/comment()[1]',
    '/Q{}r[1]/text()[2]',
    '/Q{}r[1]/processing-instruction("p")[1]',
    '/Q{}r[1]/text()[3]',
    '/Q{}r[1]/Q{urn:x}e[1]',
    '/Q{}r[1]/Q{urn:x}e[2]',
    '/Q{}r[1]/Q{}e[1]',
    '/Q{}r[1]/text()[4]',
    '/Q{}r[1]/Q{}f[1]',
    '/Q{}r[1]/Q{}g[1]',
    '/Q{}r[1]/Q{}g[1]/comment()[1]',
    '/comment()[2]',
    '/processing-instruction("pi0")[2]');

function U(const S: string): TLandrixXmlUtf8;
begin
  Result := LandrixXmlStringToUtf8(S);
end;

{ Finds the n-th node (1-based) of a kind with a local name ('' = any). }
function NodeOf(T: TLandrixXmlXPathTree; Kind: TLandrixXmlXPathNodeKind; const LocalName: string;
  N: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to T.Count - 1 do
    if (T.Kind[I] = Kind) and ((LocalName = '') or (T.LocalNameUtf8(I) = U(LocalName))) then
    begin
      Dec(N);
      if N = 0 then
      begin
        Result := I;
        Exit;
      end;
    end;
  Result := -1;
end;

procedure CheckTree(T: TLandrixXmlXPathTree; const Mode: string);
var
  Root, A1, A2, B, Attr, I, Text: Integer;
begin
  CheckEquals(Ord(xnkDocument), Ord(T.Kind[0]), Mode + ': document node');
  Root := T.DocumentElement;
  Check(Root > 0, Mode + ': root element');
  CheckEqualsUtf8(U('Inv'), T.LocalNameUtf8(Root), Mode + ': root local name');
  CheckEqualsUtf8(U('r:Inv'), T.NameUtf8(Root), Mode + ': root name');
  CheckEqualsUtf8(U('urn:r'), T.NamespaceUriUtf8(Root), Mode + ': root namespace');
  CheckEquals(0, T.Parent[Root], Mode + ': root parent');
  { the comment before the root is a child of the document }
  CheckEquals(Ord(xnkComment), Ord(T.Kind[T.FirstChild(0)]), Mode + ': comment first');
  { two attributes right after the element, no namespace declarations }
  CheckEquals(2, T.AttributeCount[Root], Mode + ': attribute count');
  Attr := Root + 1;
  CheckEquals(Ord(xnkAttribute), Ord(T.Kind[Attr]), Mode + ': attribute kind');
  CheckEqualsUtf8(U('id'), T.LocalNameUtf8(Attr), Mode + ': attribute name');
  CheckEqualsUtf8(U(''), T.NamespaceUriUtf8(Attr), Mode + ': attribute without namespace');
  CheckEqualsUtf8(U('7'), T.ValueUtf8(Attr), Mode + ': attribute value');
  CheckEqualsUtf8(U('r:x'), T.NameUtf8(Attr + 1), Mode + ': prefixed attribute');
  CheckEquals(Root, T.Parent[Attr], Mode + ': attribute parent');
  CheckEquals(-1, T.NextSibling[Attr], Mode + ': attribute has no sibling');
  { white space is kept: the first child is the text before <a> }
  I := T.FirstChild(Root);
  CheckEquals(Ord(xnkText), Ord(T.Kind[I]), Mode + ': white space kept');
  { text and CDATA merged }
  A1 := NodeOf(T, xnkElement, 'a', 1);
  Text := T.FirstChild(A1);
  CheckEqualsUtf8(U('one two'), T.ValueUtf8(Text), Mode + ': text and CDATA merged');
  CheckEquals(-1, T.NextSibling[Text], Mode + ': one text node');
  CheckEqualsUtf8(U('urn:d'), T.NamespaceUriUtf8(A1), Mode + ': default namespace');
  A2 := NodeOf(T, xnkElement, 'a', 2);
  CheckEquals(-1, T.FirstChild(A2), Mode + ': empty element');
  CheckEquals(A2, T.SubtreeEnd[A2], Mode + ': empty subtree');
  CheckEquals(T.ExpandedName[A1], T.ExpandedName[A2], Mode + ': same expanded name');
  CheckEquals(T.ExpandedName[A1], T.FindExpandedName(U('urn:d'), U('a')), Mode + ': find expanded name');
  CheckEquals(-1, T.FindExpandedName(U(''), U('a')), Mode + ': unknown expanded name');
  B := NodeOf(T, xnkElement, 'b', 1);
  CheckEqualsUtf8(U('tail'), T.StringValueUtf8(B), Mode + ': string value skips comment and PI');
  CheckEqualsUtf8(U('data'), T.ValueUtf8(NodeOf(T, xnkProcessingInstruction, '', 1)), Mode + ': PI value');
  CheckEqualsUtf8(U('pi'), T.LocalNameUtf8(NodeOf(T, xnkProcessingInstruction, '', 1)), Mode + ': PI target');
  CheckEqualsUtf8(U(#10'  one two'#10'  '#10'  tail'#10'  three'#10), T.StringValueUtf8(Root),
    Mode + ': string value of the root');
  CheckEquals(T.Count - 1, T.SubtreeEnd[0], Mode + ': document subtree');
  { order: every child after its parent, inside its subtree }
  for I := 1 to T.Count - 1 do
  begin
    Check(T.Parent[I] < I, Mode + ': parent before child');
    Check(T.SubtreeEnd[T.Parent[I]] >= T.SubtreeEnd[I], Mode + ': subtree nested');
  end;
  { SchXslt locations }
  CheckEqualsUtf8(U('/Q{urn:r}Inv[1]'), T.LocationPathUtf8(Root), Mode + ': root location');
  CheckEqualsUtf8(U('/Q{urn:r}Inv[1]/@Q{}id'), T.LocationPathUtf8(Attr), Mode + ': attribute location');
  CheckEqualsUtf8(U('/Q{urn:r}Inv[1]/Q{urn:d}a[2]'), T.LocationPathUtf8(A2), Mode + ': second a');
  CheckEqualsUtf8(U('/Q{urn:r}Inv[1]/Q{urn:d}a[3]'), T.LocationPathUtf8(NodeOf(T, xnkElement, 'a', 3)),
    Mode + ': third a, after b');
  CheckEqualsUtf8(U('/Q{urn:r}Inv[1]/Q{urn:d}b[1]/text()[1]'), T.LocationPathUtf8(T.SubtreeEnd[B]),
    Mode + ': text location');
  CheckEqualsUtf8(U('/Q{urn:r}Inv[1]/Q{urn:d}b[1]/comment()[1]'), T.LocationPathUtf8(T.FirstChild(B)),
    Mode + ': comment location');
  CheckEqualsUtf8(U('/Q{urn:r}Inv[1]/Q{urn:d}b[1]/processing-instruction("pi")[1]'),
    T.LocationPathUtf8(NodeOf(T, xnkProcessingInstruction, '', 1)), Mode + ': PI location');
  CheckEqualsUtf8(U('/'), T.LocationPathUtf8(0), Mode + ': document location');
  CheckEquals(Length(SaxonLocations) + 1, T.Count, Mode + ': node count as Saxon');
  for I := 1 to T.Count - 1 do
    CheckEqualsUtf8(U(SaxonLocations[I - 1]), T.LocationPathUtf8(I), Mode + ': location of node ' + IntToStr(I));
end;

procedure TestFromReader;
var
  T: TLandrixXmlXPathTree;
begin
  T := TLandrixXmlXPathTree.Create;
  try
    T.LoadFromUtf8(U(Sample));
    CheckTree(T, 'reader');
    CheckEquals(3, T.Line[T.DocumentElement], 'line of the root');
    Check(T.DomNode[T.DocumentElement] = nil, 'no DOM node');
  finally
    T.Free;
  end;
end;

procedure TestFromDocument;
var
  T: TLandrixXmlXPathTree;
  Doc: TLandrixXmlDocument;
  Root, Attr: Integer;
begin
  Doc := TLandrixXmlDocument.Create;
  T := TLandrixXmlXPathTree.Create;
  try
    Doc.LoadFromUtf8(U(Sample));
    T.LoadFromDocument(Doc);
    CheckTree(T, 'DOM');
    Root := T.DocumentElement;
    Check(T.DomNode[Root] = Doc.Root, 'DOM node of the root');
    Attr := Root + 2;
    Check(T.DomNode[Attr] = Doc.Root, 'attribute: its element');
    CheckEqualsUtf8(U('r:x'), Doc.Root.AttributeNameUtf8(T.DomAttributeIndex[Attr]), 'attribute index');
  finally
    T.Free;
    Doc.Free;
  end;
end;

procedure TestEmptyAndReload;
var
  T: TLandrixXmlXPathTree;
begin
  T := TLandrixXmlXPathTree.Create;
  try
    T.LoadFromUtf8(U('<x/>'));
    CheckEquals(2, T.Count, 'document and element');
    CheckEqualsUtf8(U(''), T.StringValueUtf8(0), 'empty string value');
    T.LoadFromUtf8(U('<y a="1"><z/></y>'));
    CheckEquals(4, T.Count, 'reloaded');
    CheckEquals(-1, T.FindExpandedName(U(''), U('x')), 'old names gone');
    CheckEqualsUtf8(U('/Q{}y[1]/Q{}z[1]'), T.LocationPathUtf8(3), 'location without namespace');
  finally
    T.Free;
  end;
end;

{ The data model rules: text split by comments and PIs, CDATA merged,
  empty CDATA no node, &amp; part of the text, prefixes for one URI,
  document-level comments and PIs, xml:lang. }
procedure TestTricky;
var
  T: TLandrixXmlXPathTree;
  Doc: TLandrixXmlDocument;
  I, Pass: Integer;
begin
  T := TLandrixXmlXPathTree.Create;
  Doc := TLandrixXmlDocument.Create;
  try
    for Pass := 1 to 2 do
    begin
      if Pass = 1 then
        T.LoadFromUtf8(U(Tricky))
      else
      begin
        Doc.LoadFromUtf8(U(Tricky));
        T.LoadFromDocument(Doc);
      end;
      CheckEquals(Length(TrickyLocations) + 1, T.Count, 'node count, pass ' + IntToStr(Pass));
      for I := 1 to T.Count - 1 do
        CheckEqualsUtf8(U(TrickyLocations[I - 1]), T.LocationPathUtf8(I),
          'location of node ' + IntToStr(I) + ', pass ' + IntToStr(Pass));
      CheckEqualsUtf8(U('t1t2t3cd&'), T.StringValueUtf8(T.DocumentElement), 'string value, pass ' + IntToStr(Pass));
      CheckEquals(T.ExpandedName[12], T.ExpandedName[13], 'a:e and b:e share the expanded name');
      Check(T.ExpandedName[13] <> T.ExpandedName[14], 'e without namespace differs');
      CheckEqualsUtf8(U('b:e'), T.NameUtf8(13), 'the prefix as written');
    end;
  finally
    Doc.Free;
    T.Free;
  end;
end;

{ Many names: the name tables grow. }
procedure TestManyNames;
var
  T: TLandrixXmlXPathTree;
  S: string;
  I, N: Integer;
begin
  S := '<r>';
  for I := 0 to 299 do
    S := S + '<p' + IntToStr(I mod 7) + ':e' + IntToStr(I) + ' xmlns:p' + IntToStr(I mod 7) + '="urn:' +
      IntToStr(I mod 13) + '" a' + IntToStr(I) + '="1"/>';
  S := S + '</r>';
  T := TLandrixXmlXPathTree.Create;
  try
    T.LoadFromUtf8(U(S));
    N := 0;
    for I := 0 to T.Count - 1 do
      if T.Kind[I] in [xnkElement, xnkAttribute] then
      begin
        Inc(N);
        CheckEquals(T.ExpandedName[I], T.FindExpandedName(T.NamespaceUriUtf8(I), T.LocalNameUtf8(I)),
          'expanded name of node ' + IntToStr(I));
      end;
    CheckEquals(601, N, 'elements and attributes');
    CheckEquals(-1, T.FindExpandedName(U('urn:99'), U('e1')), 'wrong namespace');
    CheckEqualsUtf8(U('/Q{}r[1]/Q{urn:5}e5[1]/@Q{}a5'), T.LocationPathUtf8(T.FirstChild(T.DocumentElement) + 11),
      'location after growth');
  finally
    T.Free;
  end;
end;

const
  NsSample =
    '<r xmlns:z="urn:z" xmlns="urn:d" xmlns:xml="http://www.w3.org/XML/1998/namespace" a="1">' +
    '<c xmlns="" xmlns:m="urn:m"><d xmlns:z="urn:z2"/></c><!--x--></r>';

{ The prefixes of an element joined with commas, in the tree's order. }
function Prefixes(T: TLandrixXmlXPathTree; Index: Integer): TLandrixXmlUtf8;
var
  P: TLandrixXmlUtf8Array;
  I: Integer;
begin
  P := T.InScopePrefixesUtf8(Index);
  Result := '';
  for I := 0 to Integer(Length(P)) - 1 do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + P[I];
  end;
end;

function Lookup(T: TLandrixXmlXPathTree; Index: Integer; const Prefix: string): TLandrixXmlUtf8;
begin
  if not T.LookupNamespace(Index, U(Prefix), Result) then
  begin
    CheckEqualsUtf8(U(''), Result, 'unbound: empty URI');
    Result := U('-');
  end;
end;

{ LookupNamespace and InScopePrefixesUtf8: nearest declaration, xmlns=""
  undeclares, xml always and once, xmlns never, attributes use their
  element, other nodes have none. }
procedure TestNamespaces;
var
  T: TLandrixXmlXPathTree;
  Doc: TLandrixXmlDocument;
  R, C, D, Pass: Integer;
  Mode: string;
begin
  T := TLandrixXmlXPathTree.Create;
  Doc := TLandrixXmlDocument.Create;
  try
    for Pass := 1 to 2 do
    begin
      if Pass = 1 then
      begin
        T.LoadFromUtf8(U(NsSample));
        Mode := 'reader';
      end
      else
      begin
        Doc.LoadFromUtf8(U(NsSample));
        T.LoadFromDocument(Doc);
        Mode := 'DOM';
      end;
      R := T.DocumentElement;
      C := T.FirstChild(R);
      D := T.FirstChild(C);
      CheckEqualsUtf8(U('urn:d'), Lookup(T, R, ''), Mode + ': default namespace');
      CheckEqualsUtf8(U('urn:z'), Lookup(T, R, 'z'), Mode + ': z on the root');
      CheckEqualsUtf8(U('-'), Lookup(T, C, ''), Mode + ': xmlns="" undeclares');
      CheckEqualsUtf8(U('urn:z2'), Lookup(T, D, 'z'), Mode + ': nearest declaration');
      CheckEqualsUtf8(U('urn:m'), Lookup(T, D, 'm'), Mode + ': inherited');
      CheckEqualsUtf8(U('-'), Lookup(T, R, 'm'), Mode + ': declared below');
      CheckEqualsUtf8(U(LandrixXmlNamespaceXml), Lookup(T, D, 'xml'), Mode + ': xml');
      CheckEqualsUtf8(U('-'), Lookup(T, R, 'xmlns'), Mode + ': xmlns is not bound');
      CheckEqualsUtf8(U('urn:z'), Lookup(T, R + 1, 'z'), Mode + ': attribute: its element');
      CheckEqualsUtf8(U('-'), Lookup(T, 0, 'z'), Mode + ': document node');
      CheckEqualsUtf8(U('-'), Lookup(T, 0, 'xml'), Mode + ': xml: not for the document node');
      CheckEqualsUtf8(U('-'), Lookup(T, T.NextSibling[C], 'z'), Mode + ': comment');
      CheckEqualsUtf8(U('z,,xml'), Prefixes(T, R), Mode + ': prefixes of the root');
      CheckEqualsUtf8(U('m,z,xml'), Prefixes(T, C), Mode + ': prefixes of c');
      CheckEqualsUtf8(U('z,m,xml'), Prefixes(T, D), Mode + ': prefixes of d');
      CheckEqualsUtf8(U('z,,xml'), Prefixes(T, R + 1), Mode + ': prefixes of an attribute');
      CheckEquals(0, Integer(Length(T.InScopePrefixesUtf8(0))), Mode + ': no prefixes for the document');
    end;
    { a DOM that lost its declarations: the names still bind their
      prefixes, a declaration wins }
    Doc.LoadFromUtf8(U('<p:r xmlns:p="urn:p" xmlns:q="urn:q" q:a="1"><p:s xmlns:p="urn:p2"/></p:r>'));
    Check(Doc.Root.RemoveAttribute(U(LandrixXmlNamespaceXmlns), U('p')), 'xmlns:p removed');
    Check(Doc.Root.RemoveAttribute(U(LandrixXmlNamespaceXmlns), U('q')), 'xmlns:q removed');
    T.LoadFromDocument(Doc);
    R := T.DocumentElement;
    D := T.FirstChild(R);
    CheckEqualsUtf8(U('urn:p'), Lookup(T, R, 'p'), 'fixup: the element name');
    CheckEqualsUtf8(U('urn:q'), Lookup(T, R, 'q'), 'fixup: an attribute name');
    CheckEqualsUtf8(U('urn:q'), Lookup(T, D, 'q'), 'fixup: from an ancestor');
    CheckEqualsUtf8(U('urn:p2'), Lookup(T, D, 'p'), 'fixup: a declaration wins');
    CheckEqualsUtf8(U('-'), Lookup(T, R, ''), 'fixup: no default namespace');
    CheckEqualsUtf8(U('p,q,xml'), Prefixes(T, R), 'fixup: prefixes of the root');
    CheckEqualsUtf8(U('p,q,xml'), Prefixes(T, D), 'fixup: prefixes of the child');
  finally
    Doc.Free;
    T.Free;
  end;
end;

{ A malformed document leaves an empty tree. }
procedure TestFailedLoad;
var
  T: TLandrixXmlXPathTree;
begin
  T := TLandrixXmlXPathTree.Create;
  try
    CheckEquals(1, T.Count, 'the document node before any load');
    CheckEquals(-1, T.DocumentElement, 'no root before any load');
    CheckEqualsUtf8(U(''), T.StringValueUtf8(0), 'empty string value before any load');
    T.LoadFromUtf8(U('<a><b/></a>'));
    try
      T.LoadFromUtf8(U('<a><b></a>'));
      FailNotRaised('malformed XML');
    except
      on E: ELandrixXmlError do
        Check(E.Code <> xecNone, 'error code');
    end;
    CheckEquals(1, T.Count, 'empty after the failed load');
    CheckEquals(-1, T.DocumentElement, 'no root after the failed load');
  finally
    T.Free;
  end;
end;

{ Copies the children of Node of Source into Target with the Build calls. }
procedure CopyChildren(Source, Target: TLandrixXmlXPathTree; Node: Integer);
var
  I, J: Integer;
  Prefixes: TLandrixXmlUtf8Array;
  Uri: TLandrixXmlUtf8;
begin
  Prefixes := nil;
  I := Source.FirstChild(Node);
  while I >= 0 do
  begin
    case Source.Kind[I] of
      xnkElement:
        begin
          Target.BuildStartElement(Source.NamespaceUriUtf8(I), Source.PrefixUtf8(I), Source.LocalNameUtf8(I));
          Prefixes := Source.InScopePrefixesUtf8(I);
          for J := 0 to Integer(Length(Prefixes)) - 1 do
            if Source.LookupNamespace(I, Prefixes[J], Uri) then
              Target.BuildNamespace(Prefixes[J], Uri);
          for J := I + 1 to I + Source.AttributeCount[I] do
            Target.BuildAttribute(Source.NamespaceUriUtf8(J), Source.PrefixUtf8(J), Source.LocalNameUtf8(J),
              Source.ValueUtf8(J));
          CopyChildren(Source, Target, I);
          Target.BuildEndElement;
        end;
      xnkText:
        Target.BuildText(Source.ValueUtf8(I));
      xnkComment:
        Target.BuildComment(Source.ValueUtf8(I));
      xnkProcessingInstruction:
        Target.BuildProcessingInstruction(Source.LocalNameUtf8(I), Source.ValueUtf8(I));
    else
      { attributes are not children }
    end;
    I := Source.NextSibling[I];
  end;
end;

{ A tree built from constructed nodes equals the loaded one. }
procedure TestBuildDocument;
var
  Loaded, T: TLandrixXmlXPathTree;
  I: Integer;
begin
  Loaded := TLandrixXmlXPathTree.Create;
  T := TLandrixXmlXPathTree.Create;
  try
    Loaded.LoadFromUtf8(U(Sample));
    T.BeginBuild(True);
    CopyChildren(Loaded, T, 0);
    T.EndBuild;
    CheckTree(T, 'built');
    CheckEquals(0, T.Line[T.DocumentElement], 'built: no line');
    Loaded.LoadFromUtf8(U(Tricky));
    T.BeginBuild(True);
    CopyChildren(Loaded, T, 0);
    T.EndBuild;
    CheckEquals(Loaded.Count, T.Count, 'tricky: node count');
    for I := 1 to T.Count - 1 do
      CheckEqualsUtf8(U(TrickyLocations[I - 1]), T.LocationPathUtf8(I), 'tricky: location of node ' + IntToStr(I));
    { text split over several calls is one node; text and empty text at
      the top of a document node }
    T.BeginBuild(True);
    T.BuildText(U('a'));
    T.BuildText(U(''));
    T.BuildText(U('b'));
    T.BuildStartElement(U(''), U(''), U('e'));
    T.BuildText(U('c'));
    T.BuildEndElement;
    T.BuildText(U('d'));
    T.EndBuild;
    CheckEquals(5, T.Count, 'document with text: node count');
    CheckEquals(Ord(xnkText), Ord(T.Kind[1]), 'text at the top');
    CheckEqualsUtf8(U('ab'), T.ValueUtf8(1), 'text merged');
    CheckEqualsUtf8(U('abcd'), T.StringValueUtf8(0), 'string value of the document');
    CheckEquals(2, T.DocumentElement, 'the element after the text');
    CheckEqualsUtf8(U('/text()[2]'), T.LocationPathUtf8(4), 'second text at the top');
  finally
    T.Free;
    Loaded.Free;
  end;
end;

procedure CheckBuildError(T: TLandrixXmlXPathTree; Step: Integer; const Msg: string);
begin
  try
    case Step of
      0: T.BuildStartElement(U(''), U(''), U('x'));
      1: T.BuildAttribute(U(''), U(''), U('a'), U('1'));
      2: T.BuildNamespace(U('p'), U('urn:p'));
      3: T.BuildEndElement;
      4: T.EndBuild;
      5: T.BuildText(U('t'));
    end;
    FailNotRaised(Msg);
  except
    on E: ELandrixXmlError do
      CheckEquals(Ord(xecInvalidOperation), Ord(E.Code), Msg);
  end;
end;

{ Trees without a document node: one node at the top, which has no
  parent; calls out of order raise xecInvalidOperation. }
procedure TestBuildWithoutDocument;
var
  T: TLandrixXmlXPathTree;
  Uri: TLandrixXmlUtf8;
begin
  T := TLandrixXmlXPathTree.Create;
  try
    T.BeginBuild(False);
    T.BuildStartElement(U('urn:e'), U('p'), U('e'));
    T.BuildNamespace(U('p'), U('urn:e'));
    T.BuildAttribute(U(''), U(''), U('a'), U('1'));
    T.BuildStartElement(U(''), U(''), U('f'));
    T.BuildText(U('x'));
    T.BuildEndElement;
    T.BuildText(U('y'));
    T.BuildEndElement;
    CheckBuildError(T, 0, 'a second node at the top');
    CheckBuildError(T, 5, 'text after the node at the top');
    T.EndBuild;
    CheckEquals(5, T.Count, 'element tree: node count');
    CheckEquals(Ord(xnkElement), Ord(T.Kind[0]), 'node 0 is the element');
    CheckEquals(-1, T.Parent[0], 'no parent');
    CheckEquals(4, T.SubtreeEnd[0], 'subtree of node 0');
    CheckEquals(-1, T.DocumentElement, 'no document element');
    CheckEqualsUtf8(U('xy'), T.StringValueUtf8(0), 'string value');
    Check(T.LookupNamespace(2, U('p'), Uri), 'a namespace declared on the top');
    CheckEqualsUtf8(U('urn:e'), Uri, 'its URI');
    CheckEquals(0, T.Parent[1], 'attribute parent');
    CheckEqualsUtf8(U('Q{http://www.w3.org/2005/xpath-functions}root()'), T.LocationPathUtf8(0),
      'location of the top');
    CheckEqualsUtf8(U('Q{http://www.w3.org/2005/xpath-functions}root()/Q{}f[1]/text()[1]'),
      T.LocationPathUtf8(3), 'location below the top');
    T.BeginBuild(False);
    T.BuildAttribute(U('urn:a'), U('q'), U('b'), U('2'));
    CheckBuildError(T, 1, 'a second attribute at the top');
    T.EndBuild;
    CheckEquals(1, T.Count, 'attribute tree');
    CheckEquals(Ord(xnkAttribute), Ord(T.Kind[0]), 'node 0 is the attribute');
    CheckEqualsUtf8(U('2'), T.StringValueUtf8(0), 'attribute value');
    Check(not T.LookupNamespace(0, U('q'), Uri), 'no namespace lookup on an attribute at the top');
    CheckEquals(0, Integer(Length(T.InScopePrefixesUtf8(0))), 'no prefixes of an attribute at the top');
    T.BeginBuild(False);
    T.BuildText(U('t'));
    T.EndBuild;
    CheckEquals(Ord(xnkText), Ord(T.Kind[0]), 'node 0 is the text');
    { errors }
    T.BeginBuild(False);
    CheckBuildError(T, 4, 'nothing built');
    CheckBuildError(T, 2, 'a namespace without element');
    CheckBuildError(T, 3, 'no element to end');
    T.BeginBuild(True);
    CheckBuildError(T, 1, 'an attribute of the document node');
    CheckBuildError(T, 3, 'the document node is not ended');
    T.BuildStartElement(U(''), U(''), U('e'));
    T.BuildComment(U('c'));
    CheckBuildError(T, 1, 'an attribute after a child');
    CheckBuildError(T, 2, 'a namespace after a child');
    CheckBuildError(T, 4, 'an element not ended');
    T.LoadFromUtf8(U('<x/>'));
    CheckBuildError(T, 0, 'no BeginBuild after a load');
  finally
    T.Free;
  end;
end;

procedure Register;
begin
  RegisterTest('XPathTree.FromReader', TestFromReader);
  RegisterTest('XPathTree.FromDocument', TestFromDocument);
  RegisterTest('XPathTree.EmptyAndReload', TestEmptyAndReload);
  RegisterTest('XPathTree.Tricky', TestTricky);
  RegisterTest('XPathTree.ManyNames', TestManyNames);
  RegisterTest('XPathTree.Namespaces', TestNamespaces);
  RegisterTest('XPathTree.FailedLoad', TestFailedLoad);
  RegisterTest('XPathTree.BuildDocument', TestBuildDocument);
  RegisterTest('XPathTree.BuildWithoutDocument', TestBuildWithoutDocument);
end;

end.
