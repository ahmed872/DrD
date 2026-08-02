text = 'Ø§Ù„ÙƒÙ„'
try:
    b = text.encode('windows-1252')
    print(b.decode('utf-8'))
except Exception as e:
    print(e)
