<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- width modifiers of fractional seconds and years; time zones with
     three digits; languages (Saxon HE names any other than en) -->
<xsl:output method="text"/>
<xsl:template match="/">
<xsl:value-of select="format-time(xs:time('12:00:00.1234'), '[f,2-2]'), format-time(xs:time('12:00:00.1'), '[f,3]'),
  format-time(xs:time('12:00:00.1'), '[f001,4]'), format-date(xs:date('2026-01-01'), '[Y01,4]'),
  format-date(xs:date('2026-01-01'), '[Y01,1-*]'), format-date(xs:date('2026-01-01'), '[Y,*-2]'),
  format-time(xs:time('12:00:00.9999999'), '[f]'), format-time(xs:time('12:00:00.9999999'), '[f0]'),
  format-time(xs:time('12:00:00+05:45'), '[Z000]'), format-time(xs:time('12:00:00-05:00'), '[Z0000]'),
  format-date(xs:date('2026-01-01'), '[Y]', '', (), ()), format-date(xs:date('2026-01-01'), '[Y]', 'EN', (), ()),
  format-date(xs:date('2026-01-01'), '[Y]', 'en-GB', (), ()), format-date(xs:date('2026-01-01'), '[Y]', (), (), ())"
  separator="|"/>
</xsl:template>
</xsl:stylesheet>
