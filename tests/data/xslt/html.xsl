<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- method html as Saxon's HTML5 serializer and indenter write it: the
     doctype, void elements, boolean attributes, escaping in text,
     attributes, script and style, URI attributes, inline and formatted
     elements, long and multi-line text, processing instructions -->
<xsl:output method="html" include-content-type="no"/>
<xsl:template match="/">
<html><head><title>T &amp; t</title><style>a > b { x: "&amp;" }</style><script>if (a &lt; b &amp;&amp; c) {}</script><meta charset="UTF-8"/></head>
<body><p>Text with <b>bold</b> and <i>italic</i> and a long line of text that goes on and on and on beyond the eighty character limit of the indenter so it may wrap</p>
<div><span>x</span><span>y</span></div><div>a&#xA0;b&#x80;c &#xE4; &lt; &gt; "q"</div>
<input type="checkbox" checked="checked" disabled="DISABLED" hidden="hidden" value="v"/><option selected="selected">o</option><br/><img src="a b/&#xE4;.png" alt="&lt;&amp;{x}&quot;'&#10;"/>
<a href="#x?a=&#xE4;&amp;b=1 2">l</a><p/><td></td><pre>  pre
  text</pre><textarea>t
x</textarea>
<p>multi
line
  text</p>
<ul><li>one</li><li>two <em>em</em></li></ul>
<xsl:comment>c</xsl:comment>
<xsl:processing-instruction name="pi">data</xsl:processing-instruction>
</body></html>
</xsl:template>
</xsl:stylesheet>
