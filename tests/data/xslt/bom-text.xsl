<?xml version="1.0" encoding="UTF-8"?>
<!-- byte-order-mark with the text method -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="text" encoding="UTF-8" byte-order-mark=" true "/>
  <xsl:template match="/"><html><body>Hello &#233;</body></html></xsl:template>
</xsl:stylesheet>
