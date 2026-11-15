<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- method xhtml: the meta elements the content type replaces, by their
     attribute names as written (charset, http-equiv) -->
<xsl:output method="xhtml" indent="no"/>
<xsl:template match="/"><html xmlns="http://www.w3.org/1999/xhtml"><head><meta HTTP-EQUIV="content-type" content="x"/><meta CHARSET="x"/><meta charset="y"/></head></html></xsl:template>
</xsl:stylesheet>
