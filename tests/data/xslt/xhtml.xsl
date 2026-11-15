<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- method xhtml: empty XHTML elements, the content type meta, URI attributes, escaping, the default indentation -->
<xsl:output method="xhtml"/>
<xsl:template match="/">
<html xmlns="http://www.w3.org/1999/xhtml"><head><meta http-equiv="Content-Type" content="x"/><title>T</title></head>
<body><p></p><br/><hr/><img src="a b&#xe4;.png" alt="&#xe4;"/><a href="x y&#xe4;?q=1&amp;r">l</a><span/><div><p>t<b>b</b></p></div><x:y xmlns:x="urn:x"/><script>if (a &lt; b) x();</script><input checked="checked"/></body></html>
</xsl:template>
</xsl:stylesheet>
