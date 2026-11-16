<?xml version="1.0" encoding="UTF-8"?>
<!-- method html: cdata-section-elements has no effect -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html" cdata-section-elements="a script"/>
  <xsl:template match="/">
    <html><body><a>x&lt;y</a><script>if (a &lt; b) x;</script></body></html>
  </xsl:template>
</xsl:stylesheet>
