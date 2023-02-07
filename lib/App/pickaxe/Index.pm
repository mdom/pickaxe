package App::pickaxe::Index;
use Mojo::Base -signatures, 'App::pickaxe::GUI::Select', 'App::pickaxe::Controller';
use Curses;
use App::pickaxe::Pager;
use App::pickaxe::Getline 'getline';
use App::pickaxe::SelectOption 'select_option', 'askyesno';
use POSIX 'strftime';

has 'config';
has 'keybindings';
has pages => sub { [] };

has helpbar =>
  "q:Quit a:Add e:Edit s:Search /:find b:Browse o:Order D:delete ?:help";

sub statusbar ($self) {
    my $base = $self->config->{base_url}->clone->query( key => undef );
    return "pickaxe: $base";
}

sub current_page ( $self ) {
    $self->pages->[ $self->current_line ];
}

has 'order' => 'reverse_updated_on';

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

sub update_pages ( $self, $key ) {
    $self->set_pages( $self->api->pages );
    display_msg("Updated.");
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

sub view_page ( $self, $key ) {
    App::pickaxe::Pager->new( config => $self->config, index => $self )->run;
    $self->render;
}

sub set_pages ( $self, $pages ) {

    my $order = $self->order =~ s/^reverse_//r;

    $pages = [ sort { $a->{$order} cmp $b->{$order} } @$pages ];

    if ( $self->order =~ /^reverse_/ ) {
        $pages = [ reverse @$pages ];
    }

    $self->pages($pages);

    my ( $fmt, @args ) = $self->compile_index_format;
    my @lines;
    my $x = 1;
    for my $page ($self->pages->@*) {
        $page->{index} = $x++;
        push @lines, sprintf( $fmt, map { $_->($page) } @args );
    }
    $self->set_lines(@lines);
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

    $self->next::method( $self->config->{keybindings} );
}

1;
