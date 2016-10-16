/*{
 "DESCRIPTION": "demonstrates the use of float-type inputs",
 "CREDIT": "by zoidberg",
 "CATEGORIES": [
 "TEST-GLSL FX"
 ],
 "INPUTS": [
 {
 "NAME": "inputImage",
 "TYPE": "image"
 },
 {
 "NAME": "level",
 "TYPE": "float",
 "DEFAULT": 0.5,
 "MIN": 0.0,
 "MAX": 1.0
 }
 ]
 }*/

void main()
{
    gl_FragColor = IMG_THIS_PIXEL(inputImage);
}
