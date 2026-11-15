<?xml version="1.0" encoding="UTF-8"?>
<!-- An imported simplified stylesheet module: its rule for "/" has the
     precedence of the import (xsl:apply-imports reaches it). -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:import href="_simplified-imported.xsl"/>
  <xsl:template match="/">
    <main>
      <xsl:apply-imports/>
    </main>
  </xsl:template>
</xsl:stylesheet>
