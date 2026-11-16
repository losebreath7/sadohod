from ..app.admin_auth import admin_token
print('\nAdmin access code (paste into the admin login):\n')
print(admin_token())
print('\nAdmin: http://127.0.0.1:8000/preview/admin.html\n')
