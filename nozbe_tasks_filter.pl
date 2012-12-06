#!/usr/bin/perl
$|=1;

my $key = "your API key"; #<--- YOU HAVE TO CONFIGURE THIS API KEY (see your profile information in Nozbe.com)

use strict;
use Data::Dumper;
use Array::Utils qw(:all);
use LWP::Simple;
use JSON;
use Wx qw(:id);
use Wx::Event qw(EVT_CHECKLISTBOX);
use Wx qw(wxPD_CAN_ABORT wxPD_AUTO_HIDE wxPD_APP_MODAL wxPD_ELAPSED_TIME wxPD_ESTIMATED_TIME wxPD_REMAINING_TIME);

#Here you can configure a set of constants to map with context_ids
# this will allow to configure @user_context_ids to download tasks only of certain 
# contexts more quickly (not all contexts).
use constant {
   context1 => "aaaaaaaa",
   context2 => "bbbbbbbbb",
   context3 => "ccccccccc",
};


#Contextos a usar (mayor velocidad)
my @user_context_ids; #download all tasks in contexts
#my @user_context_ids = (context1, context2); #download only tasks from context1 and 2 (but you need to know the ids)

#### MAIN ###
my $frame; ##ventana principal
my $tasksVisible_list; ##lista de tareas (vista)
my $project_view; ##lista de proyectos (vista)
my @hashTasksVisible;  ##lista de tareas(hash) visibles

###--- carga CONTEXTOS y PROYECTOS ---###

## Currently if I show two ProgressDialog the application crash
#my $dialog = Wx::ProgressDialog->new( 'Loading data from Nozbe...',
#                                          'Loading Contexts',
#                                          2, undef,
#                                          wxPD_CAN_ABORT|wxPD_AUTO_HIDE|
#                                          wxPD_APP_MODAL|wxPD_ELAPSED_TIME );

my $content;
my $json = new JSON;
my $continue;

## -- Obtiene los contextos de Nozbe
$content = get("http://www.nozbe.com/api/contexts/key-".$key);
print "content: $content\n";
my $context_list = $json->decode($content);

#si no está definido los contextos a usar (user_context_ids) utiliza todos
#pero si está definido los filtra para usar sólo los definidos
if(@user_context_ids){
	my @new_context_list;
	
	##get element in @$context_list que están en @user_context_ids
	foreach my $context_id (@user_context_ids){
		#get context information for this context_id
		my @context_info = grep {$_->{id} eq $context_id} @$context_list;
		push (@new_context_list, @context_info);
	}
	
	#actualiza la lista de contexto con la nueva lista
	$context_list = \@new_context_list;
}



#actualiza el diálogo
#$continue = $dialog->Update( 1, "Loading Projects" );

## -- Obtiene los proyectos de Nozbe
$content = get("http://www.nozbe.com/api/projects/key-".$key);
print "content: $content\n";
my $project_list = $json->decode($content);

#finaliza el dialogo
#$dialog->Destroy;

###--- END : carga de CONTEXTOS Y PROYECTOS ---###


###--- carga TAREAS ---###

my $context_number = @$context_list;
print "numero de contextos:".$context_number."\n";
my $dialog2 = Wx::ProgressDialog->new( 'Loading Tasks from Nozbe..',
                                          'Loading Tasks',
                                          $context_number, undef,
#                                          wxPD_CAN_ABORT|wxPD_AUTO_HIDE|
#                                          wxPD_APP_MODAL|wxPD_ELAPSED_TIME 
                                          );

## -- Obtiene las tareas de cada proyecto y las almacena

## Almacén de todas las TAREAS (hash por project_id) (hash por task_id)
my %tasksByProjectID = ();

#bucle para cada contexto
my $context_index=1;
foreach my $context (@$context_list) {
	#last if $context_index==3;
	###actualiza el diálogo
	my $message = "Loading context: ".$$context{name};
	print "($context_index) $message\n";
	$continue = $dialog2->Update($context_index, $message );

	#obtiene las tareas del projecto actual
	$content = get("http://www.nozbe.com/api/actions/what-context/id-".$$context{"id"}."/key-".$key);
	print "content=$content\n";
	my $tasks;
	if($content ne "null"){
		print "decodifica el contenido\n";
		$tasks = $json->decode($content); ##array ref
	}else{## if content==null ref a un array vacío.
		print "tareas []\n";
		$tasks =[];
	}
	
	#guarda en la información del contexto el número de tareas
	$context->{ntasks}=scalar @$tasks;
	
	#guarda las tareas en un hash (por project_id)

	foreach my $task (@$tasks){
		print "guarda tarea ($task->{id}) en project($task->{project_id})\n";
		store_task($task);
	}
	
	#incrementa el project_index
	$context_index++;
}

##Guardas los nombres de los CONTEXTOS
my @context_names;
foreach my $context (@$context_list) {
	print "--$$context{name}--\n";
	#calcula el número de tareas de este contexto
	push(@context_names, "".$$context{name}." (".$$context{ntasks}.")");
	
	## Añade un campo "visible" FALSE para todos
	$$context{visible}=0;
}

##Guardas los nombres de los PROYECTOS
my @project_names;
foreach my $project (@$project_list) {
	##Crea un array de tasks_ids para contarlos
	my @task_ids = keys %{$tasksByProjectID{$$project{id}}};
	print "--$$project{name}--\n";
	push(@project_names, "".$$project{name}." (".scalar @task_ids.")");

	## Añade un campo "visible" FALSE para todos
	$$project{visible}=0;
}



##Guarda la tarea en tasksByProjectID
#convierte context information en array y actualiza su valor
sub store_task{
	my ($task) = @_;
	print "store_task:$task\n";
	
	#Si es una tarea completada, no hace nada
	if($task->{done}==1){
	   return;
	}
	
	#mira si esa tarea ya está guardada en el hash tasksByProjectID
	my $project_id = $task->{project_id};
	my $task_id    = $task->{id};
	if(  (exists $tasksByProjectID{$project_id}) &&
	     (exists $tasksByProjectID{$project_id}->{$task_id}) ){
		print "tarea ya existe, añade nuevo contexto:".$task->{context_name}."\n";
		#añade al correspondiente array context_id y context_name
		push( @{$tasksByProjectID{$project_id}->{$task_id}->{context_id}}, $task->{context_id} );
		push( @{$tasksByProjectID{$project_id}->{$task_id}->{context_name}}, $task->{context_name} );
	}else{
		print "tarea no existe\n";
		print "Task(".$task->{context_name}."): ".$task->{name}."\n";

		#convierte context_id y context_name en un arrayref
		$task->{context_id}=[$task->{context_id}];
		$task->{context_name}=[$task->{context_name}];
	
		###añade la tarea en el hash		
		## añade el hashByID en el hashByProjectID
		$tasksByProjectID{$project_id}{$task_id}=$task;
	}
}

##marca como "hecha" la tarea en Nozbe
sub check_task{
	my($task) = @_; #hash ref
    get("https://webapp.nozbe.com/api/check/ids-".$task->{id}."/key-".$key);
}

#Borra una tarea del modelo
#Actualiza la vista
sub remove_task{
	my($task) = @_; #hash ref
	
	##borra task de tasksByProjectID
	delete $tasksByProjectID{$task->{project_id}}{$task->{id}};
	
	updateTasksVisible();
}


#print "Lista final con todos los proyectos:\n";
#print "tasksByProjectID=";print Dumper \%tasksByProjectID;

#finaliza el dialogo
$dialog2->Destroy;

###--- END : carga de TAREAS ---###

##Lista de tareas a monstrar
my @tasksVisible;

####################################################################################
###### Actualiza las TAREAS VISIBLES según PROYECTOS y CONTEXTOS seleccionados #####
####################################################################################
sub updateTasksVisible{
	print "actualiza tareas visibles\n";
	
	##Inicializa la lista, array vacío
	@tasksVisible=();
	
	##crea array de contextIDVisible
	my @contextsIDVisible = ();
	
	foreach my $context (@$context_list){
		print "Context:".$$context{name}."(".$$context{visible}.")\n";
		if($$context{visible}!=0){
			#añade el context_id en el array de context_id visibles
			print "context_id=". $$context{id}."\n";
			push (@contextsIDVisible, $$context{id});
		}
	}
    #print "contextsIDVisible=";print Dumper \@contextsIDVisible;

	
	#Array para guardar las tareas completas (hash) con toda la información
	@hashTasksVisible=();
	
	##Lo primero es filtrar por proyectos (si no hay tareas entonces se puede salir)
	#recorre los projectos buscando visibles
	my $i=0; ## es necesario conocer el índice del proyecto
	print "recorre la lista de projectos\n";
    foreach my $project (@$project_list) {
    	print "Projecto:".$$project{name}."(".$$project{visible}.")\n";
    	if($$project{visible}!=0){
    		##Añade las tareas de este proyecto al array de tareas visibles
    		#por cada tarea añade el nombre
    		print "Añade tareas de ".$$project{name}."(".$$project{id}.")\n";
    		
    		#foreach my $task (@{$tasksByProjectIndex[$i]}){
    		#	print "".$task."\n";
    		#	print "tarea: ".$$task{name}."\n";
    		#	push(@hashTasksVisible, $task);
    		#}
    		#coge el arrayref de tasksByProjectID (es un hash_ref by TaskID)
    		my $tasks_ref = $tasksByProjectID{$$project{id}};
    		push(@hashTasksVisible, values %$tasks_ref);
    	}
    	#actualiza el indice
    	$i++;
    }
    if( scalar(@hashTasksVisible)==0 ){ #No hay ninguna tarea
        #Actualiza la vista de tareas (sin tareas)
	    $tasksVisible_list->SetItems(\@tasksVisible);
    	return;
    }
    
    ##Elimina las tareas que no tengan los contextos seleccionados
    print "Elimina las tareas que no tiene los contextos seleccionados...\n";

    my $i=0;
    do {
    	my $task = $hashTasksVisible[$i];
		##saca la intersección de task.contextIDs con contextsIDVisible
		my $contextIntersection = intersect( @{$task->{context_id}}, @contextsIDVisible );
		print "task:".$task->{name}." contextIntersection=$contextIntersection\n";
		if($contextIntersection!=scalar(@contextsIDVisible)){
		    #si no tiene todos los contextos marcados, borra esa entrada del array
		    print "elimina tarea($i):".$$task{name}."\n";
		    print "i=$i\n";
	    	splice(@hashTasksVisible, $i, 1);
	    }else{ #se aumenta el index si no se borra la entrada
	    	$i++;
	    }
	}while($i<=$#hashTasksVisible);
	
	##Finalmente actualiza las tareas visibles
	#print "Final hashTasksVisible="; print Dumper @hashTasksVisible;
	foreach my $task (@hashTasksVisible) {
		push (@tasksVisible, $$task{name});
	}

    #Actualiza la vista de tareas
    $tasksVisible_list->SetItems(\@tasksVisible);
    
    #Actualiza el titulo de la ventana
    $frame->SetTitle("Nozbe, task selected: ". @tasksVisible);
}


##### LOOP principal de la aplicación #####
package NozbeFilter;

use base 'Wx::App';
use Wx qw(wxID_EXIT);
use Wx::Event qw(EVT_MENU);
use Wx qw(wxDefaultPosition wxDefaultSize wxSUNKEN_BORDER wxTAB_TRAVERSAL wxSP_3DBORDER
			wxSP_3DSASH wxNO_BORDER wxHORIZONTAL wxVERTICAL wxGROW);

####################################
# OnInit: Dibuja la ventana principal de la aplicación
####################################
sub OnInit {
  my $self = shift;

  #########################
  ##crea la ventana principal 
  $frame = Wx::Frame->new(
    undef,
    -1,
    'Nozbe filtering',
    &Wx::wxDefaultPosition,
    [1200,700]
  );
  #Tamaño mínimo
  $frame->SetMinSize([450,350]);

  my $sizerHor = Wx::BoxSizer->new( wxHORIZONTAL );
  $frame->SetSizer($sizerHor);

  #añade Splitter
  my $splitter = Wx::SplitterWindow->new($frame, -1, wxDefaultPosition, wxDefaultSize,
                                    wxSP_3DBORDER|wxSP_3DSASH|wxNO_BORDER);
  $splitter->SetMinimumPaneSize(100);
  $splitter->SetSashPosition(200);

  my $panel1 = Wx::Panel->new($splitter,-1,wxDefaultPosition, [200,200], wxSUNKEN_BORDER|wxTAB_TRAVERSAL);
  my $panel2 = Wx::Panel->new($splitter,-1,wxDefaultPosition, [1000,200], wxSUNKEN_BORDER|wxTAB_TRAVERSAL);
  
  $splitter->SplitVertically($panel1, $panel2, 200);
  $sizerHor->Add($splitter, 1, wxGROW, 5);

  
  
  #Añadir los "sizers" para añadir los elementos
  #Sizer para contextos y proyectos
  my $sizerIzq = Wx::BoxSizer->new( wxVERTICAL );
  $panel1->SetSizer($sizerIzq);
  
  my $sizerDer = Wx::BoxSizer->new( wxHORIZONTAL );
  $panel2->SetSizer($sizerDer);

  #espacio
  $sizerIzq->AddSpacer(5);
  #Añade a la ventana los CONTEXTOS
  my $context_list = MyApp::ContextList->new($panel1);
  $sizerIzq->Add($context_list, 1, &Wx::wxEXPAND);

  #espacio entremedio
  $sizerIzq->AddSpacer(5);

  #Añade a la ventana los PROYECTOS
  $project_view = MyApp::ProjectList->new($panel1);
  $sizerIzq->Add($project_view, 1, &Wx::wxEXPAND);
  #espacio abajo
  $sizerIzq->AddSpacer(5);

  
  #espacio
  $sizerDer->AddSpacer(5);    
  #Añade ventana lista de TAREAS
  $tasksVisible_list = MyApp::TasksVisibleList->new($panel2);
  $sizerDer->Add($tasksVisible_list, 5, &Wx::wxEXPAND);
  #espacio
  $sizerDer->AddSpacer(5);    


##-- Añade el MENU para Quit --##
  # Create menus
  our @id = (0 .. 100); # IDs array
  
  my $firstmenu = Wx::Menu->new();
  $firstmenu->Append($id[0], "(Un)Mark all projects\tCTRL-M");
  $firstmenu->Append($id[1], "New Task in Inbox\tCTRL-N");
  $firstmenu->Append(wxID_EXIT, "Exit");
  
  # Create menu bar
  my $menubar   = Wx::MenuBar->new();
  $menubar->Append($firstmenu, "Nozbe filter");

  # Attach menubar to the window
  $frame->SetMenuBar($menubar);
  $frame->SetAutoLayout(1);

  # Handle events Menú
  EVT_MENU( $self, $id[0], \&markUnmarkAllProjects );
  EVT_MENU( $self, $id[1], \&newTask );
  EVT_MENU( $self, wxID_EXIT, sub {$frame->Close(1)} );
##-- fin MENU --##
  
  
  $frame->Show;

}

######
# Arranca la aplicación

NozbeFilter->new->MainLoop;

exit 0;

################
# (Des)Marca todas (dependiendo de la primera)
sub markUnmarkAllProjects {
  my($this, $event) = @_;
  
  #chequea el primer project y cambia todos en base a el
  my $num_elements = @$project_list;
  my $mark = !($project_view->IsChecked( 0 ));

  for(my $i=0; $i<$num_elements; $i++ ){
  	  #actualiza la vista
	  $project_view->Check($i, $mark);
	  #actualiza el modelo
	  $$project_list[$i]{visible}=$mark;
  }
  
  #actualiza las tareas
  main::updateTasksVisible();
}

#--
# Menú: new Task in Inbox
sub newTask {
  my($this, $event) = @_;
  #Load MyApp::NewTaskWindow that performs all the work
  MyApp::NewTaskWindow->new->Show;
}

#########################################
##### Clase para lista de contextos #####
package MyApp::ContextList;
use base 'Wx::CheckListBox';
use Wx qw(wxDefaultPosition wxDefaultSize);
use Wx::Event qw(EVT_CHECKLISTBOX);

sub new {
  my $class = shift;
  my $this = $class->SUPER::new( $_[0], -1, wxDefaultPosition,
                                 wxDefaultSize,
                                 [ @context_names ] );

  EVT_CHECKLISTBOX( $this, $this, \&OnCheckContext );

  return $this;
}

### Click en un CONTEXT
sub OnCheckContext {
  my( $this, $event ) = @_;

  my $i = $event->GetInt();
  print "Context:".$$context_list[$i]{name}."\n";
  $$context_list[$i]{visible}=$this->IsChecked( $i );
  
  main::updateTasksVisible();
}


#########################################
##### Clase para lista de PROYECTOS #####
package MyApp::ProjectList;
use base 'Wx::CheckListBox';
use Wx qw(wxDefaultPosition wxDefaultSize);
use Wx::Event qw(EVT_CHECKLISTBOX);

sub new {
  my $class = shift;
  my $this = $class->SUPER::new( $_[0], -1, wxDefaultPosition,
                                 wxDefaultSize,
                                 [ @project_names ] );

  EVT_CHECKLISTBOX( $this, $this, \&OnCheckProject );

  return $this;
}

### Click en un PROJECT
sub OnCheckProject {
  my( $this, $event ) = @_;

  #actualiza la visibilidad del proyecto seleccionado
  my $i = $event->GetInt();
  print "Project:".$$project_list[$i]{name}."\n";
  $$project_list[$i]{visible}=$this->IsChecked( $i );
  main::updateTasksVisible();
}

######

############################
##### TasksVisibleList #####
package MyApp::TasksVisibleList;
use base 'Wx::CheckListBox';
use Wx qw(wxDefaultPosition wxDefaultSize wxOK wxCANCEL wxTheClipboard);
use Wx::Event qw(EVT_MENU EVT_CHECKLISTBOX EVT_LISTBOX_DCLICK);
use Wx::DND;

use constant {
   TASK_GONOZBE   => 531,
   TASK_CLIPBOARD => 532,
};

sub new {
  my $class = shift;
  my $this = $class->SUPER::new( $_[0], -1, [220,10],
                                 [-10,-10],
                                 [ @tasksVisible ] );

  #handle checkbox
  EVT_CHECKLISTBOX( $this, $this, \&OnCheckTask );
  #handle doble-click on task
  EVT_LISTBOX_DCLICK( $this, $this, \&OnSelectTask );
  #handle right-click on task
  Wx::Event::EVT_MOUSE_EVENTS($this, \&MouseEventHandler);

  # Handle events Popup Menú
  print "Popup menu handlers...\n";
  EVT_MENU( $this, TASK_GONOZBE, \&GoNozbe );
  EVT_MENU( $this, TASK_CLIPBOARD, \&CopyTaskOnClipboard );


  return $this;
}

#Cuando una tarea se completa
sub OnCheckTask {
  my( $this, $event ) = @_;
  my $i = $event->GetInt();


  my ($answer) = Wx::MessageBox("Complete task?", "Confirm",
                          wxOK | wxCANCEL, undef);
  if ($answer == wxOK){
  	my $task = $hashTasksVisible[$i];
  	main::check_task($task);
  	main::remove_task($task);
  }else{
  	#cancela quita el chequeo
  	$this->Check($i, 0);
  }
}

#saca más información de la tarea para el messageBox
sub nice_print {
	my($task)=@_;
	
	my $description = "[".$task->{project_name}."] ".$task->{name}."\n".
			"Contexts:@{$$task{context_name}}";
};

#cuando una tarea se selecciona con doble-click
sub OnSelectTask {
  my( $this, $event ) = @_;
  
  my $i = $event->GetInt();
  my $task = $hashTasksVisible[$i];

  Wx::LogMessage( nice_print($task) );

}

#cuando se pulso el botón derecho del raton
sub OnItemRightClick {
  my ($this, $event) = @_;
  
  print "show popup menu...\n";
  my $popup_menu = Wx::Menu->new();
  $popup_menu->Append(TASK_GONOZBE, "Show in &Nozbe.com");
  $popup_menu->Append(TASK_CLIPBOARD, "&Copy task description");
  $this->PopupMenu( $popup_menu, $event->GetX, $event->GetY);

}

#Popup menú : se quiere mostrar una tarea en Nozbe.com
use Browser::Open qw( open_browser );

sub GoNozbe {
  my( $this, $event ) = @_;

  print "GoNozbe...\n";

  #Obtiene la tarea seleccionada  
  my $selected = $this->GetSelection;
  
  if($selected==-1){
	  Wx::LogMessage( "First: Select a Task" );
	  return;
  }
  
  #Open Nozbe for the corresponding task
  my $task = $hashTasksVisible[$selected];
  my $url = "https://webapp.nozbe.com/account/new#project_".$task->{project_id};
  #print "OS: $^O\n";
  open_browser($url);
}

# Popup menú: se quiere copiar el texto de la tarea seleccionada en el clipboard
sub CopyTaskOnClipboard {
  my( $this, $event ) = @_;

  print "Copying task in Clipboard...\n";

  #Obtiene la tarea seleccionada  
  my $selected = $this->GetSelection;
  
  if($selected==-1){
	  Wx::LogMessage( "First: Select a Task" );
	  return;
  }

  my $text = $this->GetString($selected);
  print "Copying: $text\n";
  
  ##manage clipboard
  my $textObject = Wx::TextDataObject->new($text);
  wxTheClipboard->Open;
  wxTheClipboard->SetData($textObject);
  wxTheClipboard->Close;
}

#Handler de los eventos del ratón en la lista de tareas
sub MouseEventHandler {
	my ($this, $event) = @_;
		
	if($event->RightUp){
		$this->OnItemRightClick($event);
	}else{
		$event->Skip(); #execute the default behaviour
	}
}

## ---- END TaskVisibleList ----

#############################################
##### Clase para ventana de nueva tarea #####
package MyApp::NewTaskWindow;
use LWP::Simple;
use Wx qw(wxDefaultPosition wxDefaultSize wxOK wxCANCEL wxVERTICAL wxHORIZONTAL wxALIGN_CENTER_VERTICAL wxALIGN_CENTER_HORIZONTAL wxALL wxGROW wxID_ADD wxID_CANCEL wxTE_PROCESS_ENTER);
use Wx::Event qw(EVT_BUTTON EVT_TEXT_ENTER);

#la caja de texto es global a la clase
my $textCtrl;

sub new {
  my $frame = Wx::Frame->new(
    undef,
    -1,
    'New Task',
    &Wx::wxDefaultPosition,
    [500,120]
  );
  
  #Define los eventos de los dos botones
  EVT_BUTTON($frame, wxID_ADD, \&addTask);
  EVT_BUTTON($frame, wxID_CANCEL, sub{$frame->Close(1)});
  EVT_TEXT_ENTER($frame, 46001, \&addTask );
  
  my $sizerVer = Wx::BoxSizer->new(wxVERTICAL);
  $frame->SetSizer($sizerVer);
  $textCtrl = Wx::TextCtrl->new($frame, 46001, "", wxDefaultPosition, wxDefaultSize, wxTE_PROCESS_ENTER );
  $sizerVer->Add($textCtrl, 0, wxGROW|wxALL, 5);

  my $sizerHoz = Wx::BoxSizer->new(wxHORIZONTAL);
  $sizerVer->Add($sizerHoz, 0, wxALIGN_CENTER_HORIZONTAL|wxALL, 5);

  my $addButton = Wx::Button->new( $frame, wxID_ADD, "Add", wxDefaultPosition, wxDefaultSize, 0 );
  $sizerHoz->Add($addButton, 0, wxALIGN_CENTER_VERTICAL|wxALL, 5);

  my $cancelButton = Wx::Button->new( $frame, wxID_CANCEL, "Cancel", wxDefaultPosition, wxDefaultSize, 0 );
  $sizerHoz->Add($cancelButton, 0, wxALIGN_CENTER_VERTICAL|wxALL, 5);
    
  return $frame;
}

## Añade una nueva tarea en Inbox
sub addTask {
	my($this, $event) = @_;
	
	#Obtiene el texto de la tarea
	my $new_task_description = $textCtrl->GetValue;
	
    get("https://webapp.nozbe.com/api/newaction/name-".$new_task_description."/key-".$key);
	
	
	$this->Close(1);
}

1;

