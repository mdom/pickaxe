package App::pickaxe::Index;
use Mojo::Base -signatures, 'App::pickaxe::Base', 'App::pickaxe::GUI::Select';

use App::pickaxe::Getline 'getline';
use App::pickaxe::Keys 'getkey';
use App::pickaxe::Pager;
use App::pickaxe::Pages;

use Curses;

use POSIX 'strftime';

has helpbar =>
  "q:Quit a:Add e:Edit s:Search /:find b:Browse o:Order D:delete ?:help";

sub statusbar ($self) {
    my $base = $self->config->{base_url}->clone->query( key => undef );
    return "pickaxe: $base";
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

sub update_current_page ($self) {
    $self->pages->set( $self->api->page( $self->pages->current->title ) );
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

sub view_page ( $self, $key ) {
    App::pickaxe::Pager->new( config => $self->config, pages => $self->pages, api => $self->api )->run;
    ## pages could be changed, so we regenerate the index
    $self->regenerate_index;
    $self->render;
}

sub sort_pages ( $self, $pages ) {
    $self->next::method( $pages );
    $self->regenerate_index;
}

sub set_pages ( $self, $pages ) {
    $self->next::method( $pages );
    $self->regenerate_index;

}

sub regenerate_index ( $self ) {
    my ( $fmt, @args ) = $self->compile_index_format;
    my @lines;
    my $x = 1;
    for my $page ( $self->pages->each ) {
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
        $self->update_pages;
    }
    elsif ( $query eq '' ) {
        $self->message('To view all messages, search for "all".');
    }
    else {
        my $pages = $self->api->search($query);

        if ( !$pages ) {
            $self->message('No matches found.');
            return;
        }
        $self->set_pages($pages);
        $self->message('To view all messages, search for "all".');
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
        $self->message("$project is not a project.");
        return;
    }

    $self->api->base_url->path("/projects/$project/");
    $self->update_pages;
}

sub sync_pages ( $self, $key ) {
    $self->update_pages;
    $self->message("Updated.");
}

sub jump ( $self, $key ) {
    $self->next::method( $key );
    $self->pages->set_index( $self->current_line );
}

sub prev_item ( $self, $key ) {
    $self->pages->prev;
}

sub run ($self) {
    $self->query_connection_details;
    $self->update_pages;

    $self->next::method( $self->config->keybindings );
}

sub render ( $self ) {
    $self->current_line( $self->pages->index );
    $self->next::method;
}

1;
