select * from _add_user(
	'sys_user',                   --tbTarget
	null,                         -- created by
	'salas.flavio@gmail.com',     -- email
	'flavio e.',                  -- first_name
	'salas m.',                   -- last_name
	'EMAIL_VERIFY',               -- status_access
	'123456',                     -- passw
	0,                            -- passw expire on days  <= 1 not expire
	false,                        -- force change password on next login
	'{1}'                         -- list roles for users @todo add rbac
);
