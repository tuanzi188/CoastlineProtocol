from fontTools import subset
import os

# All Chinese characters used in the game
chinese = '一三上下与东中为主交人仓伏休伤低体余作你佳使侧倒候停储充入全公共关典内再决准出击分创利到前剩剿动包北匣区医半单南卧压原发取受右同名后向听命和回圈在地场坡垬域境声备复外多头奔始存安完宸对寻射就尽局屏山岛岸巡左已幸库度开式弹当形往径待得快态恢惕意成战房手找抗护拖拾持指按挑换据排探推掩提搜摇操收效敌敏数整新时景暂最未本杆束来杩枪标核格模次正步段汰治活流测浜浪海涘淘清湀滅滑滩火灵点爆物率环生用由甲界留疗疾的目瞄硬示离秒移稍空突立站等算线练结给继绪续缩者耗胜脊脚自药菜蓝行补装西观视角触警认训请跃跑路跳蹲转边返追退通逻部重野量鈥鎹鎼键镜闃闯闲间阔面靶音骸默鼠'

# ASCII printable
ascii_chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,;:!?@#$%^&*()_+-=<>[]{}/\\|~'
ascii_chars += chr(39) + chr(34)

chars = chinese + ascii_chars

opts = subset.Options()
opts.glyph_names = False
opts.recalc_bounds = True
opts.notdef_outline = True
opts.layout_features = []
opts.name_IDs = []
opts.name_legacy = False
opts.name_languages = []
opts.drop_tables = ['DSIG']

ss = subset.Subsetter(options=opts)
font = subset.load_font('assets/simhei.ttf', opts)
ss.populate(text=chars)
ss.subset(font)
font.save('assets/simhei_subset.ttf')

orig = os.path.getsize('assets/simhei.ttf')
new = os.path.getsize('assets/simhei_subset.ttf')
print(f'Original: {orig/1024/1024:.1f} MB')
print(f'Subset: {new/1024:.0f} KB')
print(f'Reduction: {(1-new/orig)*100:.0f}%')
