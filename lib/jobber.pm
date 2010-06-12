package jobber;
use Dancer ':syntax';

use strict;
use DBI;
use Digest::MD5 qw(md5_hex); 

use Data::Dump qw(dump);

our $VERSION = '0.1';

my $dbh;

before sub {
    $dbh = DBI->connect("dbi:SQLite:dbname=db/vacancies.db","","");
};

get '/' => sub {
    my $sth = $dbh->prepare("SELECT * FROM vacancies ORDER BY vac_date DESC") or die "Can't prepare statement: $DBI::errstr";
    $sth->execute;
    my $table;
    layout 'empty';
    while(my $row = $sth->fetchrow_hashref) {
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
	};
    }
    layout 'main';
    template 'index', { jobs => $table };
};

get '/vacancy/:code' => sub {
    if (params->{code} =~ /^\d+$/) {
	my $sth = $dbh->prepare("SELECT * FROM vacancies v
				    JOIN users u ON (u.usr_id=v.usr_id) 
				    WHERE v.vac_id=?") or die($dbh->errstr);
	$sth->execute(params->{code});
	my $table;
	layout 'empty';
	if(my $row = $sth->fetchrow_hashref) {
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
	    };
	}
	layout 'main';
	template 'index', { jobs => $table };
    } else {
	template 'empty', {'body' => 'strange vacancy code'};
    }
};

get '/add' => sub {
    template 'register';
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

    $sth = $dbh->prepare("SELECT * FROM users where usr_email=? and usr_password=?");
    $sth->execute( params->{vac_owner_email}, md5_hex(params->{vac_owner_password}) );
    my $row = $sth->fetchrow_hashref;
    
    if($row->{usr_id}) {
	$usr_id = $row->{usr_id};
    } else {
	$sth = $dbh->prepare("INSERT INTO users (usr_email, usr_password, usr_company_name, usr_name, usr_phone, usr_site, usr_logo, usr_jt, usr_jt_show)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);");
	$sth->execute(params->{vac_owner_email}, md5_hex(params->{vac_owner_password}), params->{vac_owner_company_name}, params->{vac_owner_name}, params->{vac_owner_phone}, 
		    params->{vac_owner_site}, params->{vac_owner_logo}, $vac_owner_jt, params->{vac_owner_jt_show} );

	$sth = $dbh->prepare("SELECT * FROM users where usr_email=? and usr_password=?");
	$sth->execute( params->{vac_owner_email}, md5_hex(params->{vac_owner_password}) );
	my $row = $sth->fetchrow_hashref;
	$usr_id = $row->{usr_id};
    }
    
    $sth = $dbh->prepare("INSERT INTO vacancies (
		    usr_id, vac_name, vac_description, vac_date, vac_date_to, 
		    vac_salary, vac_experense, vac_schedule, vac_employment, 
		    vac_city, vac_country, vac_moderate
	    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);");
    
    $sth->execute($usr_id, params->{vac_name}, params->{vac_description}, time, (time+params->{vac_livetime}*8640), params->{vac_salary}, params->{vac_experense}, 
		    params->{vac_schedule}, params->{vac_employment}, params->{vac_city}, params->{vac_country}, params->{vac_moderate} );


    template 'register_done';
};

get '/install' => sub {
    template 'install';
};

post '/install' => sub {
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
		    usr_jt_show boolean
	    );");
    $dbh->do("INSERT INTO users (usr_email, usr_password, usr_name) VALUES ('admin\@localhost', '".md5_hex('admin')."' , 'administrator')");
    
    template 'empty', {'body' => 'database was created'};

};

true;
