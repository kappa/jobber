package jobber;
use Dancer ':syntax';

use strict;

use DBI;
use Digest::MD5 qw(md5_hex); 
use String::Clean::XSS;

use Data::Dump qw(dump);

our $VERSION = '0.3';

my ($dbh, $r);
my $user_login_type = 0;
my $session_timeout = 3600; 	#session t/o in sec

=sql USAGE
my $r = sql("SELECT * FROM table WHERE column=?", $name);
print $_->{id} foreach @{$r};
print $r->[0]{id};
=cut
sub sql {
    my $query = shift;
    my @params = map {(defined)?convert_XSS($_):$_} @_;
    my $sth = $dbh->prepare($query) || die($dbh->errstr,' in query ', $query);
    my $rv = $sth->execute(@params);
    my @result;

    if($sth->{NUM_OF_FIELDS}) {    
	while(my ($r) = $sth->fetchrow_hashref()) {
	    last unless defined($r);
	    push @result, $r;
	}
    }
    
    $sth->finish();
    return \@result;
}

=before
if user is login, then delete old sessions, update user's session and select user type
no type - no layout
=cut
before sub {
    $dbh = DBI->connect("dbi:SQLite:dbname=db/vacancies.db","","");
    if( cookies->{user}{value} ne "" ) {
	sql("DELETE FROM auth WHERE auth_date<?", time);
	sql("UPDATE auth SET auth_date=? WHERE auth_value=?", time+$session_timeout, cookies->{user}{value});
	$r = sql("SELECT * FROM auth a JOIN users u ON (a.auth_usr_id=u.usr_id) 
		    WHERE a.auth_date>? AND a.auth_value=?", time, cookies->{user}{value});
	$user_login_type = $r->[0]{usr_type} if $r->[0];
    }
    set layout => 'login_admin' if $user_login_type==15;
    set layout => 'login' if $user_login_type==1;
};

=index page
=cut
get '/' => sub {
    $r = sql("SELECT * FROM vacancies WHERE vac_date_to>=? ORDER BY vac_date DESC", time);
    my $table;
    foreach my $row (@$r) {
	my ($sec, $min, $hour, $day, $month, $year) = (localtime($row->{vac_date}))[0,1,2,3,4,5,6];
	$month++; 
	$year=1900+$year;
	$table .= template 'index_row', {
		'id' => $row->{vac_id}, 
		'name' => $row->{vac_name}, 
		'description' => $row->{vac_description},
		'city' => $row->{vac_city},
		'country' => $row->{vac_country},
		'salary' => $row->{vac_salary}, 
		'date' => "$year-$month-$day $hour:$min",
		'user_type' => $user_login_type,
	},
	{layout => 0};
    }

#$table .= "!".cookies->{user}{value}."!\n";

    template 'index', { jobs => $table };
};

=header /login
=cut
get '/login' => sub {
    template 'login';
};

post '/login' => sub {
    $r = sql("SELECT * FROM users WHERE usr_email=? AND usr_password=?", params->{login}, md5_hex(params->{password}));
    if($r->[0]{usr_email}) {
	my $auth = md5_hex(rand().rand());
	set_cookie 'user' => $auth;
	sql("DELETE FROM auth WHERE auth_usr_id=?", $r->[0]{usr_id});
	sql("INSERT INTO auth (auth_value, auth_usr_id, auth_date) 
		VALUES (?, ?, ?)", $auth, $r->[0]{usr_id}, time+$session_timeout);
	redirect uri_for('/login/done');
    } else {
	redirect uri_for('/login');
    }
};

get '/login/done' => sub {
    template 'login_done';
};

get '/exit' => sub {
    sql("DELETE FROM auth WHERE auth_value=?", cookies->{user}{value});
    set_cookie 'user' => "";
    redirect uri_for('/');
};

=edit profiles
=cut
get '/profile' => sub {
    $r = sql("SELECT * FROM auth a JOIN users u ON (a.auth_usr_id=u.usr_id) 
		WHERE a.auth_date>? AND a.auth_value=?", time, cookies->{user}{value});
    if ($r->[0]{usr_id}) {
	redirect uri_for('/profile/'.$r->[0]{usr_id});
    } else {
	redirect uri_for('/login');
    }
};

get '/profile/:id' => sub {
    if (params->{id} =~ /^\d+$/) {
	$r = sql("SELECT auth_usr_id FROM auth WHERE auth_value=? AND auth_usr_id=?", cookies->{user}{value}, params->{id});
	if ( $user_login_type != 15 && $r->[0]{auth_usr_id} != params->{id} ) {
	    redirect uri_for('/login');
	}
	$r = sql("SELECT * FROM users WHERE usr_id=?", params->{id});
	template 'profile', {
	    i => sub{@$r},
	    jt => sub{my $_=shift; return substr ($r->[0]{usr_jt}, $_, 1) if $r->[0]{usr_jt} && length ($r->[0]{usr_jt}) >$_ },
	};
    } else {
	redirect uri_for('/login');
    }
};

post '/profile/:id' => sub {
    if (params->{id} =~ /^\d+$/) {
	$r = sql("SELECT auth_usr_id FROM auth WHERE auth_value=? AND auth_usr_id=?", cookies->{user}{value}, params->{id});
	if ( $user_login_type != 15 && $r->[0]{auth_usr_id} != params->{id} ) {
	    redirect uri_for('/login');
	}
	my $vac_owner_jt;
	$vac_owner_jt .= params->{"vac_owner_jt[$_]"} ? params->{"vac_owner_jt[$_]"} : 0 for (0..11);
	sql("UPDATE users SET usr_email=?, usr_password=?, usr_company_name=?, usr_name=?, 
		usr_phone=?, usr_site=?, usr_logo=?, usr_jt=?, usr_jt_show=?
		WHERE usr_id=?",
		params->{vac_owner_email}, md5_hex(params->{vac_owner_password}), 
		params->{vac_owner_company_name}, params->{vac_owner_name}, params->{vac_owner_phone}, 
		params->{vac_owner_site}, params->{vac_owner_logo}, $vac_owner_jt, 
		params->{vac_owner_jt_show}, params->{id} );

	redirect uri_for('/profile/'.params->{id});
    } else {
	redirect uri_for('/login');
    }
};

=users list and delete
=cut
get '/users' => sub {
    redirect uri_for('/login') unless $user_login_type == 15;
    $r = sql("SELECT * FROM users ORDER BY usr_id DESC");
    template 'users', {
	'users' => sub{@$r},
    };
};

get '/users/delete/:id' => sub {
    redirect uri_for('/login') unless $user_login_type == 15;
    if (params->{id} =~ /^\d+$/) {
	sql("DELETE FROM vacancies WHERE usr_id=?", params->{id});
	sql("DELETE FROM users WHERE usr_id=?", params->{id});
    }
    redirect uri_for('/users');
};

=show vacancy
=cut
get '/vacancy/:code' => sub {
    if (params->{code} =~ /^\d+$/) {
	$r = sql("SELECT * FROM vacancies v JOIN users u ON (u.usr_id=v.usr_id) 
		    WHERE v.vac_id=?", params->{code});
	my $table;
	if(my $row = $r->[0]) {
	    my ($sec, $min, $hour, $day, $month, $year) = (localtime($row->{vac_date}))[0,1,2,3,4,5,6];
	    $month++; 
	    $year=1900+$year;
	    $table .= template 'index_vacancy', {
	    	'id' => $row->{vac_id}, 
	    	'name' => $row->{vac_name}, 
		'description' => $row->{vac_description},
		'city' => $row->{vac_city},
		'country' => $row->{vac_country},
		'salary' => $row->{vac_salary}, 
		'date' => "$year-$month-$day $hour:$min", 
		'experense' => $row->{vac_experense},
		'schedule' => $row->{vac_schedule},
		'employment' => $row->{vac_employment},
		'owner_email' => $row->{usr_email},
		'owner_company_name' => $row->{usr_company_name},
		'owner_phone' => $row->{usr_phone},
		'owner_site' => $row->{usr_site},
		i => sub{@$r},
		jt => sub{my $_=shift; return substr ($r->[0]{usr_jt}, $_, 1) if $r->[0]{usr_jt} && length ($r->[0]{usr_jt}) >$_ },
	    },
	    {layout => 0};
	}
	template 'index', { jobs => $table };
    } else {
	template 'empty', {'body' => 'strange vacancy code'};
    }
};

=delete vacancy
=cut
get '/delete/:code' => sub {
    redirect uri_for('/login') unless $user_login_type && $user_login_type == 15;
    if (params->{code} =~ /^\d+$/) {
	$r = sql("DELETE FROM vacancies WHERE vac_id=?", params->{code});
    }
    redirect uri_for('/');
};

=add vacancy
=cut
get '/add' => sub {
    $r = sql("SELECT * FROM auth a JOIN users u ON (a.auth_usr_id=u.usr_id) 
		WHERE a.auth_date>? AND a.auth_value=?", time, cookies->{user}{value});
    my $usr_id = $r->[0]{usr_id};
    template 'register', {
	usr_id => $usr_id,
    };
};

post '/add' => sub {

    my ($sth, $usr_id, $vac_owner_jt);

    params->{vac_owner_jt_show} = 0 unless params->{vac_owner_jt_show};
    params->{vac_schedule} = "full day" unless (params->{vac_schedule});
    params->{vac_employment} = "full-time" unless (params->{vac_employment});
    params->{vac_schedule} = "full day" unless params->{vac_schedule} =~ /^(full day|flexible schedule)$/;
    params->{vac_employment} = "full-time" unless params->{vac_employment} =~ /^(full-time|part-time|project work)$/;
    params->{vac_livetime} = 62 if (params->{vac_livetime} > 62);

    $vac_owner_jt .= params->{"vac_owner_jt[$_]"} ? params->{"vac_owner_jt[$_]"} : 0 for (0..11);

    $r = sql("SELECT * FROM auth a JOIN users u ON (a.auth_usr_id=u.usr_id) 
		WHERE a.auth_date>? AND a.auth_value=?", time, cookies->{user}{value});
    if($r->[0]) {
	$r = sql("SELECT * FROM users where usr_id=?", $r->[0]{usr_id});
    } else {
	$r = sql("SELECT * FROM users where usr_email=? and usr_password=?", 
		params->{vac_owner_email}, md5_hex(params->{vac_owner_password}) );
    }
    my $row = $r->[0];
    
    if($row->{usr_id}) {
	$usr_id = $row->{usr_id};
    } else {
	sql("INSERT INTO users (usr_email, usr_password, usr_company_name, usr_name, usr_phone, usr_site, usr_logo, usr_jt, usr_jt_show, usr_type)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1);",
		params->{vac_owner_email}, md5_hex(params->{vac_owner_password}), params->{vac_owner_company_name}, params->{vac_owner_name}, params->{vac_owner_phone}, 
		params->{vac_owner_site}, params->{vac_owner_logo}, $vac_owner_jt, params->{vac_owner_jt_show} );

	$r = sql("SELECT * FROM users where usr_email=? and usr_password=?",
		    params->{vac_owner_email}, md5_hex(params->{vac_owner_password}) );
	$usr_id = $r->[0]{usr_id};
    }
    
    sql ("INSERT INTO vacancies (
	    usr_id, vac_name, vac_description, vac_date, vac_date_to, 
	    vac_salary, vac_experense, vac_schedule, vac_employment, 
	    vac_city, vac_country, vac_moderate
	    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
	    $usr_id, params->{vac_name}, params->{vac_description}, time, (time+params->{vac_livetime}*8640), params->{vac_salary}, params->{vac_experense}, 
	    params->{vac_schedule}, params->{vac_employment}, params->{vac_city}, params->{vac_country}, params->{vac_moderate} );

    template 'register_done';
};

get '/install' => sub {
    redirect uri_for('/login') unless $user_login_type == 15;
    template 'install';
};

post '/install' => sub {
    redirect uri_for('/login') unless $user_login_type == 15;
    if (params->{password} ne 'admin') {
	return template 'empty', {'body' => 'хуй'} ;
    }
    $dbh->do("DROP TABLE vacancies");
    $dbh->do("create table vacancies (
		    vac_id integer not null primary key, 
		    usr_id integer, 
		    vac_name varchar(100), 
		    vac_description text,
		    vac_date timestamp,
		    vac_date_to timestamp,
		    vac_salary varchar(30),
		    vac_experense varchar(64),
		    vac_schedule varchar(30),
		    vac_employment varchar(30),
		    vac_city varchar(50),
		    vac_country varchar(50),
		    vac_moderate boolean default false
	    );");

    $dbh->do("DROP TABLE auth");
    $dbh->do("create table auth (
		    auth_id integer not null primary key, 
		    auth_value varchar(64),
		    auth_date integer,
		    auth_usr_id integer
	    );");

    $dbh->do("DROP TABLE users");
    $dbh->do("create table users (
		    usr_id integer not null primary key, 
		    usr_email varchar(100),
		    usr_password varchar(32),
		    usr_company_name varchar(30),
		    usr_name varchar(126),
		    usr_phone varchar(20),
		    usr_site varchar(200),
		    usr_logo varchar(300),
		    usr_jt varchar(12),
		    usr_jt_show boolean,
		    usr_type integer
	    );");
    $dbh->do("INSERT INTO users (usr_email, usr_password, usr_name, usr_type) 
		    VALUES ('admin\@localhost', '".md5_hex('admin')."' , 'administrator', 15)");
    
    template 'empty', {'body' => 'database was created'};

};

true;
