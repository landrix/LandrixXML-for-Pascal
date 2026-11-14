<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- URI attributes are escaped in NFC, by the names of an element without
     a prefix in any namespace; not on a prefixed one -->
<xsl:output method="html" indent="no"/>
<xsl:template match="/">
  <html><a href="cafe&#x301;.html"/><a xmlns="urn:foreign" href="caf&#xe9;.html" checked="checked"/>
  <x:a xmlns:x="urn:x" href="caf&#xe9;"/><A HREF="caf&#xe9;"/></html>
</xsl:template>
</xsl:stylesheet>
