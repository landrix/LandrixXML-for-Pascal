<?xml version="1.0" encoding="UTF-8"?>
<!-- method html: doctype-public alone gives a declaration named html, for
     any first element -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html" doctype-public="-//W3C//DTD HTML 4.01//EN"/>
  <xsl:template match="/">
    <xsl:comment>c</xsl:comment>
    <div><p>x</p></div>
  </xsl:template>
</xsl:stylesheet>
