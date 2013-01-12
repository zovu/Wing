package Wing::Role::Result::Site;

use Wing::Perl;
use Ouch;
use Moose::Role;
with 'Wing::Role::Result::Field';
with 'Wing::Role::Result::Shortname';
with 'Wing::Role::Result::Hostname';
with 'Wing::Role::Result::UserControlled';

after wing_apply_fields => sub {
    my ($class) = @_;
    $class->wing_fields(
        name    => {
            dbic    => { data_type => 'varchar', size => 60, is_nullable => 0 },
            view    => 'public',
            edit    => 'required',
        },
        trashed                 => {
            dbic    => { data_type => 'tinyint', default_value => 0 },
        },
        database_name           => {
            dbic    => { data_type => 'varchar', size => 50, default_value => 0 },
            indexed => 'unique'
        },
    );
};

after wing_finalize_class => sub {
    my ($class) = @_;
    $class->meta->add_after_method_modifier('shortname', sub {
        my ($self, $name) = @_;
        if (scalar @_ >= 2 && !$self->in_storage) {
            my $objects = $self->result_source->schema->resultset($class);
            if ($self->in_storage) {
                $objects = $objects->search({ id => { '!=' => $self->id }});
            }
            my $counter = '';
            my $shrink = sub {
                my $total_length = length($name) + length($counter);
                if ($total_length > 50) {
                    my $overage = $total_length - 48;
                    $name = substr($name, 0, $total_length - $overage);
                }
            };
            $shrink->();
            while ($objects->search({ database_name => $name.$counter })->count) {
                $counter++;
                $shrink->();
            }
            $name .= $counter;
            $self->database_name($name);
        }
    });
};

around sqlt_deploy_hook => sub {
    my ($orig, $self, $sqlt_table) = @_;
    $orig->($self, $sqlt_table);
    $sqlt_table->add_index(name => 'idx_find_by_shortname', fields => ['shortname','trashed']);
    $sqlt_table->add_index(name => 'idx_find_by_hostname', fields => ['hostname','trashed']);
};

after insert => sub {
    my ($self) = @_;
    $self->create_database;
};

before delete => sub {
    my ($self) = @_;
    $self->destroy_database;
};

sub trash {
    my $self = shift;
    $self->trashed(1);
    $self->hostname(undef);
    $self->update({shortname => '_'.$self->shortname}); # do this to override the validation
}

sub connect_to_database {
    my $self = shift;
    my $config = Wing->config;
    my @dsn = @{$config->get('db')};
    $dsn[0] = $config->get('tenants/db_driver/prefix') . $self->database_name . $config->get('tenants/db_driver/suffix');
    my $class = $config->get('tenants/namespace').'::DB';
    return $class->connect(@dsn);
}

sub create_database {
    my $self = shift;
    my $dbh = $self->result_source->schema->storage->dbh;
    $dbh->do("create database if not exists ".$dbh->quote_identifier($self->database_name));
    my $db = $self->connect_to_database;
    $db->deploy({ add_drop_table => 1 });
    $db->storage->disconnect;
}

sub destroy_database {
    my $self = shift;
    my $dbh = $self->result_source->schema->storage->dbh;
    $dbh->do("drop database if exists ".$dbh->quote_identifier($self->database_name));
}

=head1 NAME

Wing::Role::Result::Site - Multi-tenancy for Wing.

=head1 SYNOPSIS

 with 'Wing::Role::Result::Site';

 # in another program
 
 my $site = Wing->db->resultset('Site')->find($id);

 $site->create_database;
 
 my $site_db = $site->connect_to_database;
 
 $site->destroy_database;

=head1 DESCRIPTION

Add this to a AppName::DB::Result::Site class in your management app. This will set up this app to control multiple tenant apps. You can create and delete instances of those apps on the fly.

B<NOTE:> We need to write up a cookbook example of this. 

1;
