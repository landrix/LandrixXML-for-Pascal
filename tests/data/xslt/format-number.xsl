<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xs="http://www.w3.org/2001/XMLSchema">
<!-- format-number(): rounding (half to even on the shortest digits of a
     double), grouping, sub-pictures, percent, per mille, NaN, infinity,
     decimal formats -->
<xsl:output method="text"/>
<xsl:decimal-format name="de" decimal-separator="," grouping-separator="." NaN=""/>
<xsl:template match="/">
<xsl:for-each select="
 format-number(xs:double('2.675'), '0.00'), format-number(2.675, '0.00'), format-number(xs:double('0.125'), '0.00'), format-number(0.125, '0.00'),
 format-number(xs:double('1e21'), '#,##0'), format-number(xs:double('1.0E-7'), '0.000000000'), format-number(xs:float('0.1'), '0.000000000000'),
 format-number(xs:double('0.1'), '0.00000000000000000000'), format-number(1234567.891, '#,##0.00'), format-number(1234567.891, '#.##0,00', 'de'),
 format-number(-1234.5, '#,##0.00;(#,##0.00)'), format-number(-1234.5, '#,##0.00'), format-number(0.5, '#.00'), format-number(0.5, '#'), format-number(0, '#'),
 format-number(0.256, '0%'), format-number(0.256, '0.0&#x2030;'), format-number(xs:double('NaN'), '0', 'de'), format-number(1 div 0e0, '0'), format-number(-1 div 0e0, '0'),
 format-number((), '0.0'), format-number(1234567, '#,###,##0'), format-number(123456789, '#,##,###'), format-number(12, '0000.0###'),
 format-number(12.3456789, '0.0###'), format-number(5, 'Total: 0 EUR'), format-number(-0.4, '0'), format-number(xs:double('-0.0'), '0.0'), format-number(2.5, '0'), format-number(3.5, '0')">
<xsl:value-of select="concat('[', ., ']&#10;')"/></xsl:for-each>
</xsl:template></xsl:stylesheet>
