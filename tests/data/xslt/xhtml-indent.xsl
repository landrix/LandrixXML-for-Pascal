<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- method xhtml with indent: the HTML indentation rules -->
<xsl:output method="xhtml" indent="yes"/>
<xsl:template match="/">
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>T</title></head>
<body><p></p><br/><div><p>t<b>b</b> more</p><ul><li>a</li><li>b</li></ul></div><pre>  x
 y</pre><span/><table><tr><td>1</td></tr></table></body></html>
</xsl:template>
</xsl:stylesheet>
