package Wing::Session;

use Moose;
use Wing::Perl;
use Data::GUID;
use URI::Escape;
use Ouch;

has db => (
    is          => 'ro',
    required    => 1,
);

has id => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        return Data::GUID->new->as_string;
    },
);

sub BUILD {
    my $self = shift;
    my $session_data = Wing->cache->get('session'.$self->id);
    if (defined $session_data && ref $session_data eq 'HASH') {
        $self->user_id($session_data->{user_id});
        $self->extended($session_data->{extended});
        $self->ip_address($session_data->{ip_address});
        $self->sso($session_data->{sso});
        $self->api_key_id($session_data->{api_key_id});
    }
}

has extended => (
    is          => 'rw',
    default     => 0,
);

has api_key_id => (
    is          => 'rw',
);

has ip_address => (
    is          => 'rw',
);

has sso => (
    is          => 'rw',
    default     => 0,
);

has user_id => (
    is          => 'rw',
    predicate   => 'has_user_id',
    trigger     => sub {
        my $self = shift;
        $self->clear_user;
    },
);

has user => (
    is          => 'rw',
    predicate   => 'has_user',
    clearer     => 'clear_user',
    lazy        => 1,
    default     => sub {
        my $self = shift;
        return undef unless $self->has_user_id;
        my $user = $self->db->resultset('User')->find($self->user_id);
        if (defined $user) {
            $user->current_session($self);
        }
        return $user;
    },
);

sub extend {
    my $self = shift;
    $self->extended( $self->extended + 1 );
    Wing->cache->set(
        'session'.$self->id,
        {
            user_id     => $self->user_id,
            extended    => $self->extended,
            sso         => $self->sso,
            api_key_id  => $self->api_key_id,
            ip_address  => $self->ip_address,
        },
        60 * 60 * 24 * 7,
    );
    return $self;
}

sub is_human {
    my $self = shift;
    if (Wing->cache->get($self->id.'_is_human')) {
        return 1;
    }
    ouch 455, 'Must verify humanity.';
}

sub end {
    my $self = shift;
    Wing->cache->remove('session'.$self->id);
    return $self;
}

sub start {
    my ($self, $user, $options) = @_;
    $self->user_id($user->id);
    $user->current_session($self);
    $self->user($user);
    $self->sso($options->{sso});
    $self->ip_address($options->{ip_address});
    $self->api_key_id($options->{api_key_id});
    return $self->extend;
}

sub describe {
    my ($self, %options) = @_;
    my $out = {
        id          => $self->id,
        object_type => 'session',
        user_id     => $self->user_id,
    };
    if (exists $options{current_user} && defined $options{current_user} && $options{current_user} eq $self->user_id) {
        $out->{extended} = $self->extended;
        $out->{ip_address} = $self->ip_address;
        $out->{sso} = $self->sso;
    }
    if ($options{include_relationships}) {
        $out->{_relationships}{user} = '/api/user/'.$self->user_id;
    }
    if ($options{include_related_objects}) {
        $out->{user} = $self->user->describe;
    }
    return $out;
}

no Moose;
__PACKAGE__->meta->make_immutable;