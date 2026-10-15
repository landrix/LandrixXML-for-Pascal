{ LandrixXml - dependency-free XML library for Delphi and Free Pascal.

  Copyright (c) 2026 Landrix Software
  Licensed under the MIT License. See the LICENSE file in the project root
  or https://opensource.org/licenses/MIT for the full license text.

  Central compiler switches. Included at the top of every unit, directly
  after the unit header. }

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
  { Note 6058 "call to subroutine marked as inline is not inlined" is about
    RTL routines (Move, CompareMem) on some targets, not about our code. }
  {$WARN 6058 OFF}
{$ENDIF}

{$B-} { short-circuit boolean evaluation }
{$H+} { long strings }
{$J-} { typed constants are read-only }
{$T-} { untyped @ operator, as in default Delphi projects }
{$X+} { extended syntax }

{$IFNDEF FPC}
  {$IF CompilerVersion >= 20.0}
    { Delphi 2009+: string = UnicodeString, Char = WideChar }
    {$DEFINE LANDRIXXML_UNICODE}
  {$IFEND}
  {$IF CompilerVersion >= 15.0}
    { Delphi 7+: the byte-level tokenizer uses pointers on purpose }
    {$WARN UNSAFE_TYPE OFF}
    {$WARN UNSAFE_CODE OFF}
    {$WARN UNSAFE_CAST OFF}
  {$IFEND}
{$ENDIF}
