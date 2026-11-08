import runpy
import ci
ci.ci.HEAD = 'e498b29fa71b8bb676af0b4836f284ec5de2d34d'
runpy.run_path(str(ci.ROOT/'docs/release-1.1.6/prepare_visual.py'), run_name='__main__')
runpy.run_path(str(ci.ROOT/'docs/release-1.1.6/verify_visual_pixels.py'), run_name='__main__')
