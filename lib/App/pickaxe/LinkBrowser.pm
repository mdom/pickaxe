package App::pickaxe::LinkBrowser;
use Mojo::Base 'App::pickaxe::UI::Index', -signatures;

has links => sub { [] };
has [ 'pages', 'api' ];
has helpbar    => "q:Quit";
has statusbar  => "pickaxe: Link Browser";
has call_pager => 0;

sub follow_link ( $self, $key ) {
    my $link = $self->links->[ $self->current_line ];
    if ( $link !~ /^http/ ) {
        my $page = $self->api->page( $link, -1 );
        if ( !$page ) {
            $self->message(qq{Can't find page "$link"});
            return;
        }
        $self->pages->set( $self->api->pages );
        $self->pages->switch_to($page);
        $self->call_pager(1);
        $self->exit_after_call(1);
        return;
    }

    use IPC::Cmd;
    IPC::Cmd::run( command => [ 'xdg-open', $link ] );
}

sub run ( $self, $bindings ) {
    $self->set_lines( @{ $self->links } );
    $self->next::method($bindings);
}

1;
