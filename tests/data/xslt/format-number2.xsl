<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- format-number(): optional digits only, percent of a double, string
     subtypes as pictures -->
<xsl:output method="text"/>
<xsl:template match="/">
<xsl:value-of select="format-number(0, '#.#'), format-number(0.001, '#,###.##'), format-number(12, '#.##'),
  format-number(100, '#.##'), format-number(1, '##.##&#x2030;'), format-number(-0.001, '#.##'),
  format-number(0, '#.##%'), format-number(xs:double('0.545'), '0%'), format-number(0.545, '0%'),
  format-number(xs:double('0.0545'), '0.0&#x2030;'), format-number(1, xs:token('0')), format-number(12, '0.##'),
  format-number(xs:double('NaN'), '0'), format-number(5, '.00')" separator="|"/>
</xsl:template>
</xsl:stylesheet>
