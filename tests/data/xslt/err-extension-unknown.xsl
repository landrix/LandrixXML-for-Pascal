<?xml version="1.0" encoding="UTF-8"?>
<!-- an extension instruction without xsl:fallback that is evaluated -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:ext="urn:ext"
    extension-element-prefixes="ext">
  <xsl:template match="/"><out><ext:foo/></out></xsl:template>
</xsl:stylesheet>
