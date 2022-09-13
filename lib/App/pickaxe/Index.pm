package App::pickaxe::Index;
use Mojo::Base -signatures, 'App::pickaxe::Controller';
use Curses;
use App::pickaxe::Pager;
use App::pickaxe::Pages;
use App::pickaxe::Getline 'getline';
use App::pickaxe::DisplayMsg 'display_msg';
use App::pickaxe::SelectOption 'select_option', 'askyesno';
use POSIX 'strftime';

has 'config';
has pages => sub { App::pickaxe::Pages->new; };

has pager => sub ($self) {
    App::pickaxe::Pager->new( pages => $self->pages, config => $self->config );
};

has help_summary =>
  "q:Quit a:Add e:Edit s:Search /:find b:Browse o:Order D:delete ?:help";

has 'order' => 'reverse_updated_on';

has 'needle';

sub status ($self) {
    my $base = $self->config->{base_url}->clone->query( key => undef );
    return "pickaxe: $base";
}

sub select ( $self, $new ) {
    return if $self->pages->empty;
    $self->pages->seek($new);
}

sub format_time ( $self, $time ) {
    my $strftime_fmt = $self->config->index_time_format;
    my $redmine_fmt  = '%Y-%m-%dT%H:%M:%SZ';

    # return gmtime->strptime( $time, $redmine_fmt )->strftime($strftime_fmt);
    ## This is a microoptimation of the above statement.
    my ( $year, $mon, $mday, $hour, $min, $sec ) = split( /[:TZ-]/, $time );
    $mon  -= 1;
    $year -= 1900;
    strftime( $strftime_fmt, $sec, $min, $hour, $mday, $mon, $year );
}

sub add_attachment ( $self, $key ) {
    my $file = getline('Attach file: ');
    endwin;
    die $file;
}

sub compile_index_format ($self) {
    my $index_fmt = $self->config->index_format;

    my $fmt = '';
    my @args;

    my %identifier = (
        n => sub { $_[0]->{index} },
        t => sub { my $t = $_[0]->{title}; $t =~ s/_/ /g; $t },
        u => sub { $self->format_time( $_[0]->{'updated_on'} ) },
        c => sub { $self->format_time( $_[0]->{'created_on'} ) },
        v => sub { $_[0]->{version} },
    );

    while (1) {
        if ( $index_fmt =~ /\G%(-?\d+(?:.\d)?)?([a-zA-Z])/gc ) {
            my ( $mod, $format ) = ( $1, $2 );
            $mod //= '';
            if ( my $i = $identifier{$format} ) {
                $fmt .= "%${mod}s";
                push @args, $i;
            }
            else {
                die "Unknown format specifier <$format>\n";
            }
        }
        elsif ( $index_fmt =~ /\G([^%]+)/gc ) {
            $fmt .= $1;
        }
        elsif ( $index_fmt =~ /\G$/gc ) {
            last;
        }
    }
    return $fmt, @args;
}

sub redraw ( $self, @ ) {
    $self->next::method;
    return if $self->pages->empty;

    my @pages = $self->pages->each;

    my $offset = $self->first_item_on_page;


    my $x = 1;
    my ( $fmt, @args ) = $self->compile_index_format;

    my $last_index = $offset + $self->maxlines - 1;
    if ( $last_index > @pages - 1 ) {
        $last_index = @pages - 1;
    }

    for my $page ( @pages[ $offset .. $last_index ] ) {
        $page->{index} = $offset + $x;

        my $line = eval {
            sprintf( $fmt, map { $_->($page) } @args );
        };
        if ($@) {
            $self->dump($page);
        }
        $line = substr( $line, 0, $COLS - 1 );
        addstring( $x, 0, $line );
        $x++;
    }
    chgat( $self->pages->pos - $offset + 1, 0, -1, A_REVERSE, 0, 0 );
}

sub delete_page ( $self, $key ) {
    return if $self->pages->empty;
    $self->next::method($key);
}

sub update_pages ( $self, $key ) {
    $self->set_pages( $self->api->pages );
    display_msg("Updated.");
}

sub find_next ( $self, $key, $direction = 1 ) {
    return if $self->pages->empty;
    if ( !$self->needle ) {
        my $prompt = 'Find title' . ( $direction == -1 ? ' reverse' : '' );
        state $history = [];
        my $needle = getline( "$prompt: ", { history => $history } );
        return if !$needle;
        $self->needle( lc($needle) );
    }
    my $needle = $self->needle;
    my @pages  = $self->pages->each;
    my $pos    = $self->pages->pos;

    my @indexes =
      $direction == -1
      ? ( reverse( 0 .. $pos - 1 ), reverse( $pos .. @pages - 1 ) )
      : ( $pos + 1 .. @pages - 1, 0 .. $pos );

    for my $i (@indexes) {
        my $page = $pages[$i];
        if ( index( lc( $page->{title} ), $needle ) != -1 ) {
            $self->select($i);
            return;
        }
    }
    $self->message("Not found.");
    return;
}

sub find ( $self, $key ) {
    $self->needle('');
    $self->find_next($key);
}

sub find_reverse ( $self, $key ) {
    $self->needle('');
    $self->find_next( $key, -1 );
}

sub find_next_reverse ( $self, $key ) {
    $self->find_next( $key, -1 );
}

my %sort_options = (
    updated => 'updated_on',
    created => 'created_on',
    title   => 'title',
);

sub set_order ( $self, $key ) {
    my $order = select_option( 'Sort', qw(Updated Created Title) );
    if ($order) {
        $self->order( $sort_options{$order} );
        $self->set_pages( $self->pages->array );
    }
}

sub set_reverse_order ( $self, $key ) {
    my $order = select_option( 'Rev-Sort', qw(Updated Created Title) );
    if ($order) {
        $self->order("reverse_$sort_options{$order}");
        $self->set_pages( $self->pages->array );
    }
}

sub jump ( $self, $key ) {
    return if $self->pages->empty;
    my $number = getline( "Jump to wiki page: ", { buffer => $key } );
    if ( !$number || $number =~ /\D/ ) {
        display_msg("Argument must be a number.");
        return;
    }
    $self->select( $number - 1 );
}

sub view_page ( $self, $key ) {
    return if $self->pages->empty;
    $self->pager->run;
    $self->redraw;
}

sub prev_page ( $self, $key ) {
    return if $self->pages->empty;
    my $pages = $self->pages;
    my $last_item_on_page =
      int( $pages->pos / $self->maxlines ) * $self->maxlines - 1;
    if ( $last_item_on_page < 0 ) {
        $self->select(0);
    }
    else {
        $self->select($last_item_on_page);
    }
}

sub first_item_on_page ($self) {
    return int( $self->pages->pos / $self->maxlines ) * $self->maxlines;
}

sub next_item ( $self, $key ) {
    $self->select( $self->pages->pos + 1 );
}

sub prev_item ( $self, $key ) {
    $self->select( $self->pages->pos - 1 );
}

sub first_item ( $self, $key ) {
    $self->select(0);
}

sub last_item ( $self, $key ) {
    $self->select( $self->pages->count - 1 );
}

sub next_page ( $self, $key ) {
    return if $self->pages->empty;
    my $first_item_on_page = $self->first_item_on_page;
    if ( $self->pages->count > $first_item_on_page + $self->maxlines ) {
        $self->select( $first_item_on_page + $self->maxlines );
    }
    else {
        $self->select( $self->pages->count - 1 );
    }
}

sub set_pages ( $self, $pages ) {

    my $order = $self->order =~ s/^reverse_//r;

    $pages = [ sort { $a->{$order} cmp $b->{$order} } @$pages ];

    if ( $self->order =~ /^reverse_/ ) {
        $pages = [ reverse @$pages ];
    }

    $self->pages->replace($pages);
}

sub search ( $self, $key ) {
    state $history = [];
    my $query =
      getline( "Search for pages matching: ", { history => $history } );
    if ( $query eq 'all' ) {
        $self->set_pages( $self->api->pages );
    }
    elsif ( $query eq '' ) {
        display_msg('To view all messages, search for "all".');
    }
    else {
        my $pages = $self->api->search($query);

        if ( !$pages ) {
            display_msg('No matches found.');
            return;
        }
        $self->set_pages($pages);
        display_msg('To view all messages, search for "all".');
    }
}

sub switch_project ( $self, $key ) {
    my %projects = map { $_ => 1 } @{ $self->api->projects };
    state $history = [];
    my $project = getline(
        'Open project: ',
        {
            history            => $history,
            completion_matches => sub ($word) {
                $word ||= '';
                my @completions;
                for my $project ( keys %projects ) {
                    if ( index( $project, $word ) == 0 ) {
                        push @completions, $project;
                    }
                }
                return @completions;
            }
        }
    );
    return if !$project;
    if ( !exists $projects{$project} ) {
        display_msg("$project is not a project.");
        return;
    }

    $self->api->base_url->path("/projects/$project/");
    $self->set_pages( $self->api->pages );
}

sub run ($self) {
    $self->query_connection_details;
    $self->set_pages( $self->api->pages );
    $self->next::method;
}

1;
