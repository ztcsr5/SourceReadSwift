"""Render local curved-surface icon studies alongside the preserved flat direction.

Usage: python -B -X utf8 scripts/render_sculptural_icons.py
CPU mesh rendering uses existing NumPy, OpenCV and Pillow; no image API calls.
"""
import json

import cv2
import numpy as np
from PIL import Image, ImageColor, ImageDraw

from generate_master_app_icon import PALETTES, REVIEW, load_review_font, paste_icon, render_experimental_icon


def cubic_curve(controls: list, parameter: np.ndarray) -> np.ndarray:
    """Evaluate a cubic edge for every longitudinal sample."""
    t = parameter[..., None]
    a, b, c, d = np.asarray(controls)
    return (1-t)**3*a+3*(1-t)**2*t*b+3*(1-t)*t*t*c+t**3*d


def build_curved_plane(edges: tuple, height: float, twist: float, offset: float = 0) -> np.ndarray:
    """Interpolate two designed edges with a shallow asymmetric vaulted cross-section."""
    u = np.linspace(.001, .999, 82)
    v = np.linspace(0, 1, 25)
    first = cubic_curve(edges[0], u)
    second = cubic_curve(edges[1], u)
    xy = first[:, None, :]*(1-v[None, :, None])+second[:, None, :]*v[None, :, None]
    bow = np.sin(np.pi*u)[:, None]
    z = offset + height*bow*np.sin(np.pi*v)[None, :]
    z += twist*bow*(v[None, :]-.5)+18*u[:, None]
    return np.concatenate([xy, z[..., None]], axis=-1)


def build_orbit() -> np.ndarray:
    """A narrow tilted ribbon passes behind and in front of the central mark."""
    u = np.linspace(0, 2*np.pi, 181)
    v = np.linspace(-1, 1, 5)
    width = 3+8*(.5+.5*np.sin(u))
    x = 512+(372+v[None, :]*width[:, None])*np.cos(u)[:, None]
    y = 518+(110+v[None, :]*width[:, None])*np.sin(u)[:, None]-.30*(x-512)
    z = np.broadcast_to((34-88*np.sin(u))[:, None], x.shape)
    return np.stack([x, y, z], axis=-1)


def mesh_colours(vertices: np.ndarray, pigment: np.ndarray) -> np.ndarray:
    """Apply broad studio illumination with a narrow grazing reflection."""
    tangent_u = np.gradient(vertices, axis=0)
    tangent_v = np.gradient(vertices, axis=1)
    normal = np.cross(tangent_u, tangent_v)
    normal /= np.maximum(np.linalg.norm(normal, axis=-1, keepdims=True), 1e-6)
    normal *= np.where(normal[..., 2:] < 0, -1, 1)
    light = np.array([-.55, -.70, .62]); light /= np.linalg.norm(light)
    half_vector = light + np.array([0, 0, 1]); half_vector /= np.linalg.norm(half_vector)
    diffuse = np.maximum(0, np.sum(normal*light, axis=-1))
    highlight = np.maximum(0, np.sum(normal*half_vector, axis=-1))**22
    rim = (1-np.maximum(normal[..., 2], 0))**4
    face = pigment*(.57+.56*diffuse[..., None])
    face += (1-face)*(.36*highlight+.20*rim)[..., None]
    # Keep the two edge highlights tiny, leaving the central area visibly its pigment.
    boundary = np.zeros(diffuse.shape)
    boundary[:, 0] = .17; boundary[:, -1] = .11
    return np.clip(face+(1-face)*boundary[..., None], 0, 1)


def rasterize_surface(target: dict, vertices: np.ndarray, colours: np.ndarray) -> None:
    """Rasterize one smooth coloured surface with interpolated depth and vertex lighting."""
    height, width = target['depth'].shape
    for row in range(vertices.shape[0]-1):
        for col in range(vertices.shape[1]-1):
            for indices in [((row,col),(row+1,col),(row,col+1)),
                            ((row+1,col),(row+1,col+1),(row,col+1))]:
                triangle = np.asarray([vertices[index] for index in indices])
                rgb = np.asarray([colours[index] for index in indices])
                left = max(0, int(np.floor(triangle[:,0].min())))
                right = min(width-1, int(np.ceil(triangle[:,0].max())))
                top = max(0, int(np.floor(triangle[:,1].min())))
                bottom = min(height-1, int(np.ceil(triangle[:,1].max())))
                if left > right or top > bottom:
                    continue
                a,b,c = triangle
                denominator = (b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
                if abs(denominator) < 1e-6:
                    continue
                y,x = np.mgrid[top:bottom+1,left:right+1]
                wa = ((b[1]-c[1])*(x-c[0])+(c[0]-b[0])*(y-c[1]))/denominator
                wb = ((c[1]-a[1])*(x-c[0])+(a[0]-c[0])*(y-c[1]))/denominator
                wc = 1-wa-wb
                depth = wa*a[2]+wb*b[2]+wc*c[2]
                patch = target['depth'][top:bottom+1,left:right+1]
                visible = (wa>=-.001)&(wb>=-.001)&(wc>=-.001)&(depth>patch)
                patch[visible] = depth[visible]
                pixels = target['colour'][top:bottom+1,left:right+1]
                interpolation = wa[...,None]*rgb[0]+wb[...,None]*rgb[1]+wc[...,None]*rgb[2]
                pixels[visible] = interpolation[visible]


def sculpture_meshes(style: str) -> list:
    """The two designs share a readable folded gesture, with independent edge control."""
    if style == 'orbit':
        upper = build_curved_plane(([(260,574),(255,323),(490,248),(755,205)],
                                    [(260,574),(418,466),(698,448),(755,205)]), 74, -65, 40)
        lower = build_curved_plane(([(280,819),(340,542),(610,560),(760,414)],
                                    [(280,819),(581,797),(779,686),(760,414)]), 62, 75, 45)
        return [upper, lower, build_orbit()]
    back = build_curved_plane(([(233,790),(355,516),(681,646),(798,340)],
                               [(233,790),(496,801),(696,792),(798,340)]), 52, -48, 15)
    front = build_curved_plane(([(233,790),(177,548),(301,292),(624,253)],
                                [(233,790),(396,632),(605,576),(624,253)]), 91, -75, 65)
    tongue = build_curved_plane(([(233,790),(393,636),(578,618),(721,505)],
                                 [(233,790),(368,724),(593,699),(721,505)]), 22, 22, 101)
    return [back, front, tongue]


def render_sculpture(style: str, palette: str) -> Image.Image:
    """Render separate coloured materials on an opaque pigment background."""
    paper, ink, _ = PALETTES[palette]
    if palette == 'peach':
        paper, ink = ink, paper
    base = np.array(ImageColor.getrgb(paper))/255.0
    pigment = np.array(ImageColor.getrgb(ink))/255.0
    size = 1280
    y,x = np.mgrid[:size,:size]/size
    illumination = .86+.14*np.exp(-((x-.20)**2+(y-.10)**2)/.7)
    ground = base*illumination[...,None]
    target = {'depth':np.full((size,size), -np.inf), 'colour':np.zeros((size,size,3))}
    for mesh in sculpture_meshes(style):
        colours = mesh_colours(mesh,pigment)
        projected = mesh.copy()
        projected[...,1] -= mesh[...,2]*.18
        projected[...,:2] *= size/1024
        rasterize_surface(target,projected,colours)
    occupied = np.isfinite(target['depth'])
    shifted = np.zeros((size,size),dtype=np.float32)
    shifted[30:,18:] = occupied[:-30,:-18]
    shadow = cv2.GaussianBlur(shifted,(0,0),24)
    ground *= (1-.32*shadow)[...,None]
    ground[occupied] = target['colour'][occupied]
    image = Image.fromarray(np.uint8(np.clip(ground,0,1)*255),'RGB')
    return image.resize((1024,1024),Image.Resampling.LANCZOS)


def render_comparison() -> dict:
    """Keep the original flat artwork visible beside both new reference-inspired studies."""
    REVIEW.mkdir(exist_ok=True)
    sheet = Image.new('RGB',(1512,1900),'#F5F1EB')
    pen = ImageDraw.Draw(sheet)
    pen.text((56,36),'纸间 / 保留平面，加入两条立体方向',font=load_review_font(32),fill='#25211E')
    columns = [('flat','01 原平面 · 保留'),('orbit','02 悬浮折面 · P1启发'),('sail','03 轻盈曲面 · P2启发')]
    for col,(_,title) in enumerate(columns):
        pen.text((56+col*488,106),title,font=load_review_font(23),fill='#25211E')
    for row,palette in enumerate(['peach','pine','klein']):
        y = 160+row*560
        for col,(style,_) in enumerate(columns):
            x = 56+col*488
            icon = render_experimental_icon(palette) if style=='flat' else render_sculpture(style,palette)
            paste_icon(sheet,icon,(x,y),424)
            paste_icon(sheet,icon,(x,y+449),48)
            pen.text((x+68,y+460),PALETTES[palette][2],font=load_review_font(18),fill='#625B55')
            icon.save(REVIEW/f'ICON-SCULPTURE-{style}-{palette}.png',optimize=True)
    path = REVIEW/'ICON-SCULPTURE-COMPARISON.png'
    sheet.save(path,optimize=True)
    return {'preview':str(path),'generation':'local CPU surface rendering; no image API'}


if __name__=='__main__':
    print(json.dumps(render_comparison(),ensure_ascii=False))
