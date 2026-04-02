#!/bin/bash
set -e

CMD=$1
ARG=$2
FLAG=$3

CONFIG_FILE=./Quadrantfile
UTILITY_NAME=quadrant

MACHINES_DIR= #"$HOME/machines_dir"
EXT_FORMATS=(qcow2 qcow qed img raw vmdk vdi vhd vhdx vpc)
SOURCE_MIRROR="https://vagrant.elab.pro/downloads/"
SOURCE_BASEIMG="https://vagrant.elab.pro/"

IF_COUNTER=1 # начало нумерации адресов
IN_GUEST_USER=vagrant

if [ -z "$CMD" ]; then
	echo "Вызов $UTILITY_NAME (init | up | status [опционально --all] | ssh [vm_name] | halt | destroy | install | uninstall)"
	exit 255; fi

if [ "$CMD" == "init" ]; then
	if [ ! -f "$CONFIG_FILE" ]; then
		cat > $CONFIG_FILE <<EOF
#	Обязательные переменные для работы утилиты
#	=======================================================
BASE_DISK=			# Путь до виртуального диска, служащего образцом (например: /home/user/base.qcow2)
SSH_PASS_KEY=		# Путь до соответствующего закрытого SSH-ключа (например: /home/user/.ssh/id_rsa_vagrant)

#	=======================================================
#	Необязательные переменные — если не указаны, скрипт подставит значения по умолчанию
#	=======================================================

# MACHINES_NAMES= 		# node1 по умолчанию
# Список имён виртуальных машин. Можно указать одну:
#   MACHINES_NAMES="app"
# Или несколько:
#   MACHINES_NAMES=("vm1" "vm2" "vm3")
# Если не указать значение, будет присвоено значение по умолчанию node1

# Для каждой машины можно задать индивидуальные параметры, используя префикс в верхнем регистре:
# {VMNAME}_{FIELD_NAME}
# Пример для машины "node1":
# NODE1_CPU="host"
# NODE1_SMP="2"
# NODE1_RAM="2048"
# NODE1_DEMON="FALSE"        # Режим отладки
# NODE1_TIMEOUT="30"         # Время ожидания загрузки системы
# NODE1_SFOLDER="./src"      # Shared Folder
# NODE1_BASE_PROVISION=("sh:./scripts/install-docker.sh" "sh:./scripts/init-swarm.sh") # Провижинг

# Доступные настройки для каждой машины:
# {VMNAME}_{FIELD_NAME}
#   _EXECUTOR    # исполняемый файл QEMU (по умолчанию: qemu-system-x86_64)
#   _CPU         # модель CPU (по умолчанию: qemu64)
#   _SMP         # количество ядер (по умолчанию: 1)
#   _RAM         # объём RAM в МБ (по умолчанию: 1024)
#   _NET_DEVICE  # сетевое устройство (по умолчанию: e1000)
#   _ADVICES     # дополнительные флаги QEMU (по умолчанию: -enable-kvm)
#   _GRAPHIC     # графический режим (по умолчанию: -nographic)
#   _DEMON       # запуск в фоне (по умолчанию: TRUE)
#   _TIMEOUT     # таймаут ожидания SSH (по умолчанию: 15)
#	_REPEAT_PROVISION	# опция для разрешения повторения продвинутого провижинга при перезапуске машин
# ===========================
# Опциональные настройки, по умолчанию поля не заданы
# ===========================
#   _SFOLDER     # путь до папки на хосте для копирования в /home/vagrant/
#   _BASE_PROVISION   # массив провижининг-задач в формате "агент:путь_к_скрипту"
#   _ADVANCE_PROVISION   # массив задач, требующих запущенного состояния для всех машин,
#	формат: "агент:путь_к_скрипту"; добавление в массив записи "repeat:multiple" даст возможность
#	повторного выполнения продвинутого провижинга ("агент:путь_к_скрипту" "repeat:multiple")
#   _INTNETS     # массив внутренних сетей в формате ("listen/5555" "connect/5555" "connect/")
#	_ADD_FORWARD	# строка, где перечисляются пробросы через user интерфейс в
#	формате: "hostfwd=tcp::n-:m"; со стороны хоста можно также указать адрес интерфеса
#	_TARGET_KEY_INJECTION	# пробрасывает SSH_PASS_KEY вовнутрь виртуальной машины

# Пример внутренних сетей (socket-сети между ВМ):
# VM1_INTNETS=("listen/5555")
# VM2_INTNETS=("connect/5555")
# VM3_INTNETS=("connect/")	# Порт сокета можно не указывать, по умолчанию подставится 5555
# Первая машина открывает сокет соединение, последующие присоединяются
#
# Пример дополнительных пробросов портов:
# MANAGER01_ADD_FORWARD="hostfwd=tcp::80-:80"
# MANAGER01_ADD_FORWARD="hostfwd=tcp::80-:80,hostfwd=tcp::443-:443" # несколько пишутся без пробелов через запятую

# =======================================================
# Подготовка базового образа
# =======================================================

# Быстрая загрузка готового образа из зеркала:
##   1. Укажи путь к боксу в переменной BASEIMG_ORIGIN
##   2. Выполни: quadrant pull
##   3. Скрипт скачает архив, извлечёт диск и обновит BASE_DISK в этом файле
## Доступные образы: https://vagrant.elab.pro/
#
# Примеры путей для BASEIMG_ORIGIN:
# BASEIMG_ORIGIN=bento/ubuntu-24.04/1.0.0/libvirt/box      # Ubuntu 24.04
# BASEIMG_ORIGIN=generic/rhel9/1.0.0/virtualbox/box        # RHEL 9
# BASEIMG_ORIGIN=debian/bullseye64/1.0.0/virtualbox/box    # Debian 11
#
# После выполнения 'quadrant pull':
##   1. Диск сохраняется в $MACHINES_DIR/ImgOrigin.<формат>
##   2. Автоматически подставляется небезопасный SSH-ключ Vagrant
##   3. Переменные BASE_DISK и SSH_PASS_KEY обновляются в этом файле
#
# Ручная подготовка образа:
##   1. Укажи путь к существующему диску в BASE_DISK
##   2. Выполни: quadrant zero run
##   3. Система запустит образ
##   4. После подготовки (пользователь, sudo, SSH) выключи ВМ — диск готов к использованию
#
# Важно: небезопасный ключ ('vagrant_insecur') предназначен ТОЛЬКО для учебных и тестовых сред
#

# =======================================================
# Опции для отладки
# =======================================================

#	_DEMON			# В значении FALSE выведет лог запуска текущей машины в окне терминала
#	_SSH_DEBUG		# В значении TRUE выведет лог проверки ssh соединения при запуске
EOF
		exit 0;
	else echo "Конфиг для текущей директории уже существует"
		exit 255; fi
fi

conf_check() {
if [ -f $CONFIG_FILE ]; then
	source "$CONFIG_FILE"
else echo "Файл конфигурации не найден в директори"
	return 255; fi
	}

machine_creator() {
	local -n OPTIONS="$1"

	if [ "${OPTIONS[ADD_FORWARD]}" != "" ]; then
		OPTIONS[ADD_FORWARD]=",${OPTIONS[ADD_FORWARD]}"; fi

	${OPTIONS[EXECUTOR]} \
	-name ${OPTIONS[NAME]} \
	${OPTIONS[ADVICES]} \
	-cpu ${OPTIONS[CPU]} \
	-smp ${OPTIONS[SMP]} \
	-m ${OPTIONS[RAM]} \
	-drive file=${OPTIONS[DISK]},if=virtio,cache=unsafe \
	-netdev user,id=net0,hostfwd=tcp::${OPTIONS[PORT]}-:22${OPTIONS[ADD_FORWARD]} \
	-device ${OPTIONS[NET_DEVICE]},netdev=net0,mac=${OPTIONS[MAC]} \
	${OPTIONS[GRAPHIC]} ${OPTIONS[INTNETS]}
	}

iface_create() {
	local INPUT="$1"
	local DEVICE="$2"
	local IFACENUM="$3"
	local VMNUM="$4"
	if [[ $INPUT =~ ^(listen|connect)/.*$ ]]; then
		local MODE=$(cut -f1 -d'/' <<< $INPUT)
		local PORT=$(cut -f2 -d'/' <<< $INPUT)
		if [[ ! $PORT =~ ^[2-9][0-9]{3}[0-9]?$ ]]; then
			PORT=5555; fi
		echo "-netdev socket,id=net${IFACENUM},${MODE}=:${PORT}" \
		"-device ${DEVICE},netdev=net${IFACENUM},mac=52:54:00:$(( 10 + VMNUM )):$(( 10 + IFACENUM )):$(( 10 + IFACENUM ))"
	else
		echo ""; fi
	}

ssh_check() {
	local PORT=$1
	local KEY="$2"
	local DEBUG="$3"
	local IN_GUEST_USER="$4"

	for i in {1..7}; do
		if [ "${DEBUG^^}" == "TRUE" ]; then
			if timeout 20 ssh -o ConnectTimeout=15 -o BatchMode=yes \
				-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
				-o GlobalKnownHostsFile=/dev/null \
				-p "$PORT" -i "$KEY" \
				${IN_GUEST_USER}@localhost true 2>&1; then
				return 0; fi
		else
			if timeout 20 ssh -o ConnectTimeout=15 -o BatchMode=yes \
				-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
				-o GlobalKnownHostsFile=/dev/null \
				-p "$PORT" -i "$KEY" \
				${IN_GUEST_USER}@localhost true >/dev/null 2>&1; then
				return 0; fi
		fi
	done
	return 127
	}

get_value() {
	local vm="$1"
	local FIELD="$2"
	local DEFAULT="$3"
	
	local VALUE="${vm^^}_${FIELD}"
	VALUE="${!VALUE}"
	VALUE="${VALUE:-$DEFAULT}"
	echo "$VALUE"
	}
	
ssh_open() {
	local port="$1"
	local key="$2"
	local user="$3"
	local name="$4"
	
	if ssh_check $port "$key" "false" $user; then
		exec ssh -p $port -i $key -o StrictHostKeyChecking=no \
		-o GlobalKnownHostsFile=/dev/null \
		-o UserKnownHostsFile=/dev/null ${user}@localhost
	else echo "$name недоступна"; fi
	}
	
share_inject() {
	local port="$1"
	local key="$2"
	local object="$3"
	local user="$4"
	
	scp -P ${port} -i "${key}" -o GlobalKnownHostsFile=/dev/null \
		-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-r "$object" \
		${user}@localhost:~/ >/dev/null 2>&1
	}

MACHINES_NAMES=${MACHINES_NAMES:-"node1"}
MACHINES_DIR=${MACHINES_DIR:-"$HOME/machines_dir"}
IN_GUEST_USER=${IN_GUEST_USER:-vagrant}

case $CMD in
"up")
	if ! conf_check; then exit 100; fi
	if [[ -n "$BASE_DISK" && -n "$SSH_PASS_KEY" ]]; then
		if [[ -f "$BASE_DISK" && -f "$SSH_PASS_KEY" ]]; then
			DISK_EXT="${BASE_DISK##*.}"
			case $DISK_EXT in
			qcow2|qcow|qed|img|raw|vmdk|vdi|vhd|vhdx|vpc)
				true
			;;
			*)
				echo "Ошибка формата"
				exit 120
			;;
			esac
			echo "Начало работы"
		else
			echo "Не найдены файл диска-источника или файл ссш-ключа"
			exit 255; fi
	else
		echo "Необходимо указать переменную базового-диска и ссш-ключ к нему"
		exit 255; fi
		
for vm in "${MACHINES_NAMES[@]}"; do
	mkdir -p $MACHINES_DIR/$vm
	if [[ ! -f "$MACHINES_DIR/$vm/disk.$DISK_EXT" ]]; then
		echo "Копируем диск..."
		if cp $BASE_DISK "$MACHINES_DIR/$vm/disk.$DISK_EXT"; then
			echo "Диск создан"
		else echo "Не удалось выполнить создание диска"; fi
	else echo "Найден существующий диск для $vm"; fi

	if [[ ! -d "$HOME/.q-drant/machines-info/$vm" ]]; then
		mkdir -p "$HOME/.q-drant/machines-info/$vm"; fi
	
	declare -A TARGET
	TARGET[NAME]="$vm"
	TARGET[EXECUTOR]=$(get_value "$vm" "EXECUTOR" "qemu-system-x86_64")	
	TARGET[CPU]=$(get_value "$vm" "CPU" "qemu64")	
	TARGET[SMP]=$(get_value "$vm" "SMP" "1")	
	TARGET[RAM]=$(get_value "$vm" "RAM" "1024")
	TARGET[DISK]="$MACHINES_DIR/$vm/disk.$DISK_EXT"
	TARGET[PORT]=$(( 2200 + IF_COUNTER ))
	TARGET[MAC]="52:54:00:00:$(( 10 + IF_COUNTER )):$(( 10 + IF_COUNTER ))"
	(( IF_COUNTER++ ))
	TARGET[NET_DEVICE]=$(get_value "$vm" "NET_DEVICE" "e1000")
	TARGET[ADD_FORWARD]=$(get_value "$vm" "ADD_FORWARD")	
	TARGET[ADVICES]=$(get_value "$vm" "ADVICES" "-enable-kvm")	
	TARGET[GRAPHIC]=$(get_value "$vm" "GRAPHIC" "-nographic")

	TARGET_INTNETS="${vm^^}_INTNETS"
	INTNETS="${!TARGET_INTNETS}"
	if [[ -n $INTNETS ]]; then
		declare -n NETS="$TARGET_INTNETS"
		TARGET_ADDNETS=()
		for iface in "${NETS[@]}"; do
			ADD=( $(iface_create $iface ${TARGET[NET_DEVICE]} $((IF_COUNTER - 1)) $IF_COUNTER) )
			TARGET_ADDNETS+=( "${ADD[@]}" )
			(( IF_COUNTER++ ))
		done
		TARGET[INTNETS]=" ${TARGET_ADDNETS[@]} "
	fi
	TARGET[DEMON]=$(get_value "$vm" "DEMON" "TRUE")

	if [ "${TARGET[DEMON]^^}" == "FALSE" ]; then
		echo "Запуск $vm"
		machine_creator TARGET
	else
		echo "Запуск $vm"
		machine_creator TARGET > $MACHINES_DIR/$vm/qemu.log 2>&1 &
 	fi

	TARGET[TIMEOUT]=$(get_value "$vm" "TIMEOUT" "15")
	sleep ${TARGET[TIMEOUT]}
	TARGET[SSH_DEBUG]=$(get_value "$vm" "SSH_DEBUG" "FALSE")

	if ssh_check ${TARGET[PORT]} "$SSH_PASS_KEY" "${TARGET[SSH_DEBUG]}" "$IN_GUEST_USER"; then
		echo "Виртуальная машина $vm запущена"
	else
		echo "Машина $vm не отвечает"
		pkill -f "qemu.*-name $vm"
		exit 255; fi
		
	TARGET_KEY_INJECTION=$(get_value "$vm" "KEY_INJECTION" "FALSE")
	if [[ "${TARGET_KEY_INJECTION^^}" == "TRUE" ]]; then
		share_inject ${TARGET[PORT]} "${SSH_PASS_KEY}" "${SSH_PASS_KEY}" "${IN_GUEST_USER}"
		echo "Ключ перенесен в $vm без настройки прав внутри"; fi
	
	TARGET_SFOLDER=$(get_value "$vm" "SFOLDER")
	if [[ -n "$TARGET_SFOLDER" && -d "$TARGET_SFOLDER" ]]; then
		share_inject ${TARGET[PORT]} "${SSH_PASS_KEY}" "$TARGET_SFOLDER" "${IN_GUEST_USER}"
		echo "Выполнен проброс папки"
	fi

	TARGET_BASE_PROVISION="${vm^^}_BASE_PROVISION"
	PROVISIONS="${!TARGET_BASE_PROVISION}"
	if [[ -n "$PROVISIONS" && ! -f "$HOME/.q-drant/machines-info/$vm/info" ]]; then
		declare -n PROVISIONS="$TARGET_BASE_PROVISION"
		for row in "${PROVISIONS[@]}"; do
			if [[ $row == *:* ]]; then
				AGENT=$(cut -f1 -d':' <<< $row)
				TASK=$(cut -f2 -d':' <<< $row)
				if [ -f "$TASK" ]; then
					scp -P ${TARGET[PORT]} -i ${SSH_PASS_KEY} \
					-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
					-o GlobalKnownHostsFile=/dev/null \
					"$TASK" ${IN_GUEST_USER}@localhost:~/ >/dev/null 2>&1
					BASETASK=$(basename "$TASK")
					ssh -p ${TARGET[PORT]} -i "$SSH_PASS_KEY" \
					-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
					-o GlobalKnownHostsFile=/dev/null \
					${IN_GUEST_USER}@localhost "chmod +x $BASETASK \
					&& $AGENT $BASETASK && rm $BASETASK" >/dev/null 2>&1
					echo "Базовый провижининг $row для $vm выполнен"
				else
					echo "Файл провижининга не найден"; fi
			else
				echo "Формат параметра провижининга не соблюден"; fi
		done
	fi

	cat > "$HOME/.q-drant/machines-info/$vm/info" <<-EOF
	PORT=${TARGET[PORT]}
	DISK_PATH="${TARGET[DISK]}"
	EOF
done
	sleep 1
	for on_vm in "${MACHINES_NAMES[@]}"; do
		source "$HOME/.q-drant/machines-info/$on_vm/info"
		ON_PORT=$PORT

		TARGET[REPEAT_PROVISION]=$(get_value "$on_vm" "REPEAT_PROVISION" "FALSE")

		if [[ "${TARGET[REPEAT_PROVISION]^^}" == "TRUE" ]]; then
			rm -f "$HOME/.q-drant/machines-info/$on_vm/advance_provisioned" 2>/dev/null; fi

		if [ ! -f "$HOME/.q-drant/machines-info/$on_vm/advance_provisioned" ]; then
		TARGET_ADVANCE_PROVISION="${on_vm^^}_ADVANCE_PROVISION"
		PROVISIONS="${!TARGET_ADVANCE_PROVISION}"
			if [[ -n "$PROVISIONS" ]]; then
				declare -n PROVISIONS="$TARGET_ADVANCE_PROVISION"
				for row in "${PROVISIONS[@]}"; do
					if [[ $row == *:* ]]; then
						AGENT=$(cut -f1 -d':' <<< $row)
						TASK=$(cut -f2 -d':' <<< $row)
						if [ -f "$TASK" ]; then
							echo "Выполняется продвинутый провижининг для $on_vm"
							scp -P ${ON_PORT} -i ${SSH_PASS_KEY} \
							-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
							-o GlobalKnownHostsFile=/dev/null \
							"$TASK" ${IN_GUEST_USER}@localhost:~/ >/dev/null 2>&1
							BASETASK=$(basename "$TASK")
							ssh -p ${ON_PORT} -i "$SSH_PASS_KEY" \
							-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
							-o GlobalKnownHostsFile=/dev/null \
							${IN_GUEST_USER}@localhost "chmod +x $BASETASK \
							&& $AGENT $BASETASK && rm $BASETASK" >/dev/null 2>&1
							sleep 2
							echo "Провижининг выполнен"
						else echo "Файл провижининга не найден"; fi
					else echo "Формат параметра провижининга не соблюден"; fi
				done
				echo "REPEAT=LOCK" > "$HOME/.q-drant/machines-info/$on_vm/advance_provisioned"
			fi
		fi
	done
;;
"status")
	if [ ! -d "$HOME/.q-drant/machines-info" ]; then
		echo "Виртуальные машины еще не создавались"
		exit 511; fi

	names=("$HOME/.q-drant/machines-info"/*/)
	if [[ ! -d "${names[0]}" ]]; then
		echo "Нет сохраненных виртуальных машин"
		exit 511; fi

	if [ "$ARG" == "--all" ]; then
		for vm in "${names[@]}"; do
			if [[ -f "${vm}/info" ]]; then
				source "${vm}/info"
				STATUS_PORT=$PORT
				STATUS_PATH="$DISK_PATH"
				vmname=$(basename $vm)
				if [ -f "$STATUS_PATH" ]; then
					if ssh_check $STATUS_PORT "$SSH_PASS_KEY" "false" $IN_GUEST_USER; then
						echo "${vmname}:${STATUS_PATH}-running"
					else
						echo "${vmname}:${STATUS_PATH}-stopped"; fi
				else echo "${vmname}-not created"; fi
			else echo "Для $vmname не найдено ИНФО"; fi
		done
	else
		if ! conf_check; then exit 100; fi
		for vm in "${MACHINES_NAMES[@]}"; do
			if [[ -f "$HOME/.q-drant/machines-info/${vm}/info" ]]; then
				source "$HOME/.q-drant/machines-info/${vm}/info"
				STATUS_PORT=$PORT
				STATUS_PATH="$DISK_PATH"
				if [ -f "$STATUS_PATH" ]; then
					if ssh_check $STATUS_PORT "$SSH_PASS_KEY" "false" $IN_GUEST_USER; then
						echo "${vm}: running"
					else echo "${vm} stopped"; fi
				else echo "${vm} not created"; fi
			else echo "Для $vm не найдено ИНФО"; fi
		done
	fi
;;
"halt")
	if ! conf_check; then exit 100; fi
	if [ ! -d "$HOME/.q-drant/machines-info" ]; then
		echo "Виртуальные машины еще не создавались"
		exit 511; fi

	names=("$HOME/.q-drant/machines-info"/*/)
	if [[ ! -d "${names[0]}" ]]; then
		echo "Нет сохраненных виртуальных машин"
		exit 511; fi

	for vm in "${MACHINES_NAMES[@]}"; do
		if [ -f "$HOME/.q-drant/machines-info/$vm/info" ]; then
			source "$HOME/.q-drant/machines-info/$vm/info"
			HALT_PORT=$PORT
			ssh -p $HALT_PORT -i $SSH_PASS_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
			-o GlobalKnownHostsFile=/dev/null \
			${IN_GUEST_USER}@localhost "sudo shutdown now" \
			>/dev/null 2>&1 || true
			sleep 4
			echo "$vm выключена"
		else echo "$vm не создана"; fi
	done
;;
"destroy")
	if ! conf_check; then exit 100; fi
	if [ ! -d "$HOME/.q-drant/machines-info" ]; then
		echo "Виртуальные машины еще не создавались"
		exit 511; fi

	for vm in "${MACHINES_NAMES[@]}"; do
		if [ -f "$HOME/.q-drant/machines-info/$vm/info" ]; then
			source "$HOME/.q-drant/machines-info/$vm/info"
			DESTROY_PATH="$DISK_PATH"
			if pgrep -af "qemu.* -name $vm " >/dev/null; then
				pkill -f "qemu.* -name $vm "
				sleep 0.5; fi
			rm -f "$DESTROY_PATH"
			rm -rf "$HOME/.q-drant/machines-info/$vm"
			rm -rf "$MACHINES_DIR/$vm"
			echo "$vm стерта"
		else echo "$vm не создана"; fi
	done
;;
"ssh")
	if ! conf_check; then exit 100; fi
	if [ -z "$ARG" ]; then
		exit 1; fi

	if [[ " ${MACHINES_NAMES[@]} " =~ " $ARG " ]]; then
		if [ -f "$HOME/.q-drant/machines-info/$ARG/info" ]; then
			source "$HOME/.q-drant/machines-info/$ARG/info"
			SSH_PORT=$PORT
			ssh_open $SSH_PORT "$SSH_PASS_KEY" $IN_GUEST_USER $ARG
		else echo "$ARG не создана"; fi
	else echo "$ARG не найдена в конфигурационном файле"; fi
;;
"install")
	source $HOME/.bashrc
	if alias | grep "${UTILITY_NAME}" >/dev/null; then
		echo "Утилита уже установлена"
		exit 1; fi

		mkdir -p "$HOME/.q-drant"
		cp "$0" "$HOME/.q-drant/${UTILITY_NAME}.sh"
		echo "alias ${UTILITY_NAME}=\"bash $HOME/.q-drant/$UTILITY_NAME.sh\"" >> $HOME/.bashrc
		echo "Для завершения установки выполните \"source ~/.bashrc\" или откройте новый терминал"
;;
"uninstall")
	source $HOME/.bashrc
	if cat $HOME/.bashrc | grep -i ${UTILITY_NAME} >/dev/null; then
		grep -vi ${UTILITY_NAME} "$HOME/.bashrc" > "$HOME/.bashrc-qd-temp"
		mv "$HOME/.bashrc-qd-temp" "$HOME/.bashrc"
		rm -r "$HOME/.q-drant"
		echo "Для завершения удаления выполните \"unalias ${UTILITY_NAME}\" или откройте новый терминал"
	else echo "Не обнаруженно записей в ~/.bashrc, нечего удалять"; fi
;;
"zero")
	if ! conf_check; then exit 100; fi
	ARG="${ARG:-run}"
	case ${ARG,,} in
	"run")
	if [ ! -f "$BASE_DISK" ]; then
		echo "Ошибка указания пути до исходного диска"
		exit 100
	else
		DISK_EXT="${BASE_DISK##*.}"
		case $DISK_EXT in
		qcow2|qcow|qed|img|raw|vmdk|vdi|vhd|vhdx|vpc)
			true
		;;
		*)
			echo "Ошибка формата"
			exit 120
		;;
		esac
		echo "Начало работы"; fi
	
	mkdir -p ~/.q-drant/base
	declare -A TARGET
	TARGET[NAME]="base"
	TARGET[EXECUTOR]=$(get_value "base" "EXECUTOR" "qemu-system-x86_64")	
	TARGET[CPU]=$(get_value "base" "CPU" "qemu64")	
	TARGET[SMP]=$(get_value "base" "SMP" "1")	
	TARGET[RAM]=$(get_value "base" "RAM" "2048")
	TARGET[DISK]="$BASE_DISK"
	TARGET[PORT]=$(( 2200 + IF_COUNTER ))
	TARGET[MAC]="52:54:00:00:$(( 10 + IF_COUNTER )):$(( 10 + IF_COUNTER ))"
	TARGET[NET_DEVICE]=$(get_value "base" "NET_DEVICE" "e1000")
	TARGET[ADD_FORWARD]=$(get_value "base" "ADD_FORWARD")	
	TARGET[ADVICES]=$(get_value "base" "ADVICES" "-enable-kvm")	
	TARGET[GRAPHIC]=$(get_value "base" "GRAPHIC" "-nographic -serial mon:stdio ")
	TARGET[DEMON]=$(get_value "base" "DEMON" "FALSE")
	if [[ "${FLAG^^}" == "--SSH" ]]; then
		TARGET[GRAPHIC]="-nographic"
		TARGET[DEMON]="TRUE"; fi
	TARGET[TIMEOUT]=$(get_value "base" "TIMEOUT" "10")
	if [ "${TARGET[DEMON]^^}" == "FALSE" ]; then
		echo "Запуск базового образа"
		machine_creator TARGET
	else
		echo "Запуск базового образа"
		machine_creator TARGET > ~/.q-drant/baseqemu.log 2>&1 &
		sleep ${TARGET[TIMEOUT]}
		if ! pgrep -af "qemu.* -name base " >/dev/null; then 
			echo "Машина из базового ораза не загрузилась"
			exit 100
		else
			echo "Base машина запущена"; fi
		if [[ "${FLAG^^}" == "--SSH" ]]; then
			if  [[ -f "$SSH_PASS_KEY" ]]; then
				ssh_open ${TARGET[PORT]} "$SSH_PASS_KEY" $IN_GUEST_USER "BASE"
			else echo "Нет ссш ключа"
				pkill -f "qemu.* -name base "
				exit 100; fi
		fi
 	fi
 	;;
 	"ssh")
		if [[ -f "$SSH_PASS_KEY" ]]; then
			ssh_open $(( 2200 + IF_COUNTER )) "$SSH_PASS_KEY" $IN_GUEST_USER "BASE"
		else echo "Нет ссш ключа"
			exit 100; fi
	;;
 	esac
;;
"pull")
	if ! conf_check; then exit 100; fi
	if [[ "${ARG^^}" == --INFO ]]; then
		echo "Содержимое зеркала"
		curl -s "$SOURCE_MIRROR"
		exit 0; fi
	if ! curl -s --head "$SOURCE_MIRROR" >/dev/null; then
		echo "Источник недоступен"
		exit 100; fi
		
	if [ -z "$BASEIMG_ORIGIN" ]; then
		echo "Не указана переменная BASEIMG_ORIGIN в конфиге для выбора образа"
		exit 200; fi
		
	if [ -f "$BASE_DISK" ]; then
		echo "Базовый диск уже существует";
		exit 1; fi
			
	if [ ! -d "$MACHINES_DIR" ]; then
		mkdir -p "$MACHINES_DIR"; fi
	mkdir -p "$MACHINES_DIR/DirBox"
		
	if wget -O- "$SOURCE_BASEIMG${BASEIMG_ORIGIN}" | tar -xz -C "$MACHINES_DIR/DirBox"; then
		true
	else echo "Не удалось скачать $SOURCE_BASEIMG${BASEIMG_ORIGIN}"
		exit 100; fi
		
	BASE_DISK="${BASE_DISK:-$MACHINES_DIR/ImgOrigin}"
	metanames=("$MACHINES_DIR/DirBox"/*)
	DISK_FILE=
	for object in "${metanames[@]}"; do
		row_ext="${object##*.}"
		case $row_ext in
		qcow2|qcow|qed|img|raw|vmdk|vdi|vhd|vhdx|vpc)
			DISK_FILE="$object"
		;;
		*)
			rm -f "$object" >/dev/null
		;;
		esac
	done
	if [[ -f "$DISK_FILE" ]]; then
		DISK_EXT="${DISK_FILE##*.}"
		BASE_DISK="${BASE_DISK%.*}.$DISK_EXT"
		mv "$DISK_FILE" "$BASE_DISK"
		sed -i "s|^BASE_DISK=.*|BASE_DISK=$BASE_DISK|" "$CONFIG_FILE"
		echo "BASE_DISK= в конфигурационном файле был обновлен"
	else
		echo "Диск в архиве не был найден"; fi
	rm -rf "$MACHINES_DIR/DirBox" >/dev/null
	if [[ "${ARG^^}" != "--NO-VAGRANT" ]]; then
		mkdir -p ~/.q-drant/common_keys
		SSH_PASS_KEY="$HOME/.q-drant/common_keys/vagrant_insecur"
		echo "Получение ssh ключа"
		curl --progress-bar -fL https://raw.githubusercontent.com/hashicorp/vagrant/main/keys/vagrant \
		-o "$SSH_PASS_KEY"
		chmod 600 "$SSH_PASS_KEY"
		sed -i "s|^SSH_PASS_KEY=.*|SSH_PASS_KEY=$SSH_PASS_KEY|" "$CONFIG_FILE"
		echo "SSH_PASS_KEY= в конфигурационном файле был обновлен"; fi
;;
esac
