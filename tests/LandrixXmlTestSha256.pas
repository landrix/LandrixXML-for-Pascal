{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Tests for LandrixXmlSha256: the FIPS 180-4 examples and every padding
  case around the block boundaries (expected values from Python's
  hashlib; the data byte I is (7 * I + 3) mod 256). }

unit LandrixXmlTestSha256;

{$I LandrixXml.inc}

interface

procedure Register;

implementation

uses
  SysUtils,
  LandrixXmlSha256,
  LandrixXmlTestFramework;

type
  TCase = record
    Size: Integer;
    Hash: string;
  end;

const
  Cases: array[0..14] of TCase = (
    (Size: 0; Hash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'),
    (Size: 1; Hash: '084fed08b978af4d7d196a7446a86b58009e636b611db16211b65a9aadff29c5'),
    (Size: 2; Hash: '323b730f87b4e7cc0948351a1c11b757b3026cda6784282576757bca21f12483'),
    (Size: 55; Hash: 'e7313d333c272e639f790978283f9eb392e843d0f29b7016828bb1daa4aac70b'),
    (Size: 56; Hash: '4324d65f3c103567f5589c710bc08f8523f929a9272e3af36fc968e52abc6c27'),
    (Size: 57; Hash: '35df609437dcfea3279283ab79fd554e2bf78f8f7ae2de532d8ee300b09e8f73'),
    (Size: 63; Hash: '81c80242132f230c3bd41b3e63bbcff16107339549214a99614ff26664625055'),
    (Size: 64; Hash: '39e3d7b6b5d075d37d053ad89b24b41bef4f3c29760c84447cab3f3be1882241'),
    (Size: 65; Hash: 'aacca6ff74fdbb296d165a45cecfa04e5127bc008770fbbdd48006f2d2fae95e'),
    (Size: 119; Hash: '9ce7368e4daf32341631b492e80359dc9f594b48453cd0dd5bf0b19279cc177e'),
    (Size: 120; Hash: '7836b787757e95e58b3ca5aec90b1b004e8deba1e50e9675af9cabf1a13a04b5'),
    (Size: 127; Hash: 'a8d23e75d936f303d248888d9b165ee543f4cbafcad3c9dd2a79bd84faa11d07'),
    (Size: 128; Hash: 'd2742f1f4ac6bb7ca2b239ee18402ba8b3f9f8e652d2a72973c2b9ba11c08cf6'),
    (Size: 129; Hash: '307f8fc2c1622b92762e818d39a185d4d667ad49a4b07ceae1f4afa008a93ec4'),
    (Size: 1000; Hash: '1e9bc38cbf860b9ec31918b065f9b52476c549a782e0e7990bed8ce3868d2371'));

function HashOf(const S: AnsiString): string;
begin
  if S = '' then
    Result := LandrixXmlSha256Hex(Pointer(nil)^, 0)
  else
    Result := LandrixXmlSha256Hex(S[1], Length(S));
end;

procedure TestExamples;
var
  S: AnsiString;
begin
  CheckEqualsStr('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', HashOf('abc'), 'abc');
  CheckEqualsStr('248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    HashOf('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'), 'two blocks');
  S := '';
  SetLength(S, 1000000);
  FillChar(S[1], Length(S), Ord('a'));
  CheckEqualsStr('cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0', HashOf(S), 'a million a');
end;

procedure TestBoundaries;
var
  I, J: Integer;
  S: AnsiString;
begin
  for I := 0 to Integer(High(Cases)) do
  begin
    S := '';
    SetLength(S, Cases[I].Size);
    for J := 1 to Cases[I].Size do
      S[J] := AnsiChar((7 * (J - 1) + 3) and $FF);
    CheckEqualsStr(Cases[I].Hash, HashOf(S), IntToStr(Cases[I].Size) + ' bytes');
  end;
end;

procedure Register;
begin
  RegisterTest('Sha256.Examples', TestExamples);
  RegisterTest('Sha256.Boundaries', TestBoundaries);
end;

end.
